// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.11;
pragma experimental ABIEncoderV2;

import "../interfaces/IDepositExecute.sol";
import "../interfaces/IRateLimiter.sol";
import "./HandlerHelpers.sol";
import "../ERC20Safe.sol";

/**
    @title Handles ERC20 and native deposits and vote executions.
    @notice This contract is intended to be used with the Bridge contract.
 */
contract IceCreamSwapERC20NativeHandler is IDepositExecute, HandlerHelpers, ERC20Safe {
    // token contract address => is burnable
    mapping(address => bool) public _burnList;

    // fee percentage, 100 = 1%
    uint256 public _feePercentage;
    // destinationDomainID => fee multiplier. 1_000 = 1x, defaults to 1x
    mapping(uint8 => uint256) public chainFeeMultipliers;
    // resourceID => fee multiplier. 1_000 = 1x, defaults to 1x
    mapping(bytes32 => uint256) public resourceFeeMultipliers;
    // destinationDomainID => resourceID => fee multiplier. 1_000 = 1x, defaults to 1x
    mapping(uint8 => mapping(bytes32 => uint256)) public individualFeeMultipliers;

    // optional rate limiter contract, if zero address, no rate limits apply
    IRateLimiter public rateLimiter;

    // this address will be interpreted as the native coin, e.g. ETH
    // as address(0) is the default value, it can be dangerous to use address(0) as native address
    address private constant NATIVE_ADDRESS = address(1);

    /**
        @param bridgeAddress Contract address of previously deployed Bridge.
        @param feePercentage fee percentage for token transfers.
     */
    constructor(address bridgeAddress, uint256 feePercentage) HandlerHelpers(bridgeAddress) {
        _setFeePercentage(feePercentage);
    }

    /**
        @notice This is just for being able to receive the native token for initially filling the handler reserves.
     */
    receive() external payable {}

    /**
        @notice A deposit is initiatied by making a deposit in the Bridge contract.
        @param resourceID ResourceID used to find address of token to be used for deposit.
        @param depositer Address of account making the deposit in the Bridge contract.
        @param data Consists of {amount} padded to 32 bytes.
        @notice Data passed into the function should be constructed as follows:
        amount                      uint256     bytes   0 - 32
        @dev Depending if the corresponding {tokenAddress} for the parsed {resourceID} is
        marked true in {_burnList}, deposited tokens will be burned, if not, they will be locked.
        @return bytes amount after fees
     */
    function deposit(
        bytes32 resourceID,
        address depositer,
        uint8 destinationDomainID,
        bytes calldata data
    ) external payable override onlyBridge returns (bytes memory) {
        uint256 amount = abi.decode(data, (uint256));

        address tokenAddress = _resourceIDToTokenContractAddress[resourceID];
        require(_contractWhitelist[tokenAddress], "invalid resourceID");

        if (address(rateLimiter) != address(0)) {
            // update rate limiter
            // if rate limit is reached, rate limiter reverts
            rateLimiter.update(resourceID, -int256(amount));
        }

        uint256 fee = _calculateFee(resourceID, destinationDomainID, amount);
        amount -= fee;

        if (tokenAddress != NATIVE_ADDRESS) {
            // handle ERC20 token
            safeTransferFrom(IERC20(tokenAddress), depositer, _bridgeAddress, fee);
            if (_burnList[tokenAddress]) {
                burnERC20(tokenAddress, depositer, amount);
            } else {
                // lockERC20 returns how many tokens were actually locked so fee tokens can be supported
                amount = lockERC20(tokenAddress, depositer, amount);
            }
        } else {
            // handle native token
            require(msg.value >= amount + fee);
            payable(_bridgeAddress).transfer(fee);
            // deposited tokens simply remain in this contract
        }

        return abi.encode(amount);
    }

    /**
        @notice Proposal execution should be initiated when a proposal is finalized in the Bridge contract.
        by a relayer on the deposit's destination chain.
        @param data Consists of {resourceID}, {amount}, {lenDestinationRecipientAddress},
        and {destinationRecipientAddress} all padded to 32 bytes.
        @notice Data passed into the function should be constructed as follows:
        amount                                 uint256     bytes  0 - 32
        destinationRecipientAddress length     uint256     bytes  32 - 64
        destinationRecipientAddress            bytes       bytes  64 - END
     */
    function executeProposal(bytes32 resourceID, bytes calldata data) external override onlyBridge {
        address tokenAddress = _resourceIDToTokenContractAddress[resourceID];
        require(_contractWhitelist[tokenAddress], "invalid resourceID");

        (uint256 amount, uint256 lenDestinationRecipientAddress) = abi.decode(data, (uint256, uint256));

        if (address(rateLimiter) != address(0)) {
            // update rate limiter
            // if rate limit is reached, rate limiter reverts
            rateLimiter.update(resourceID, int256(amount));
        }

        address recipientAddress;
        {
            // local closure to decode recipientAddress
            bytes memory destinationRecipientAddress;
            bytes20 recipientAddressBytes;

            destinationRecipientAddress = bytes(data[64:64 + lenDestinationRecipientAddress]);
            assembly {
                recipientAddressBytes := mload(add(destinationRecipientAddress, 0x20))
            }
            recipientAddress = address(recipientAddressBytes);
        }

        if (tokenAddress != NATIVE_ADDRESS) {
            // ERC20 unlocking/minting
            if (_burnList[tokenAddress]) {
                mintERC20(tokenAddress, recipientAddress, amount);
            } else {
                releaseERC20(tokenAddress, recipientAddress, amount);
            }
        } else {
            // native coin unlocking
            payable(recipientAddress).transfer(amount);
        }
    }

    /**
        @notice First verifies {contractAddress} is whitelisted, then sets {_burnList}[{contractAddress}]
        to true.
        @param contractAddress Address of contract to be used when making or executing deposits.
     */
    function setBurnable(address contractAddress, bool burnable) external onlyBridgeAdmin {
        require(_contractWhitelist[contractAddress], "!whitelisted");
        require(contractAddress != NATIVE_ADDRESS, "native");
        _burnList[contractAddress] = burnable;
    }

    function updateRateLimiter(address _rateLimiter) external onlyBridgeAdmin {
        rateLimiter = IRateLimiter(_rateLimiter);
    }

    function calculateFee(
        bytes32 resourceID,
        address, // depositer
        uint8 destinationDomainID,
        bytes calldata data
    ) external view override returns (address feeToken, uint256 fee) {
        uint256 amount = abi.decode(data, (uint256));

        feeToken = _resourceIDToTokenContractAddress[resourceID];
        require(_contractWhitelist[feeToken], "invalid resourceID");

        fee = _calculateFee(resourceID, destinationDomainID, amount);
    }

    function setFeePercentage(uint256 feePercentage) external onlyBridgeAdmin {
        _setFeePercentage(feePercentage);
    }

    function setFeeMultiplierChain(uint8 domainId, uint256 feeMultiplier) external onlyBridgeAdmin {
        chainFeeMultipliers[domainId] = feeMultiplier;
    }

    function setFeeMultiplierResource(bytes32 resourceId, uint256 feeMultiplier) external onlyBridgeAdmin {
        resourceFeeMultipliers[resourceId] = feeMultiplier;
    }

    function setFeeMultiplierIndividual(
        uint8 domainId,
        bytes32 resourceId,
        uint256 feeMultiplier
    ) external onlyBridgeAdmin {
        individualFeeMultipliers[domainId][resourceId] = feeMultiplier;
    }

    function _setFeePercentage(uint256 feePercentage) internal {
        require(feePercentage <= 10000, "invalid fee");
        _feePercentage = feePercentage;
    }

    function _calculateFee(
        bytes32 resourceId,
        uint8 destinationDomainID,
        uint256 tokenAmount
    ) internal view returns (uint256 fee) {
        fee = (tokenAmount * _feePercentage) / 10_000;

        if (individualFeeMultipliers[destinationDomainID][resourceId] != 0) {
            // fee for individual chain token combination
            fee = (fee * individualFeeMultipliers[destinationDomainID][resourceId]) / 1_000;
        } else {
            if (chainFeeMultipliers[destinationDomainID] != 0) {
                // chain fee multiplier
                fee = (fee * chainFeeMultipliers[destinationDomainID]) / 1_000;
            }
            if (resourceFeeMultipliers[resourceId] != 0) {
                // token fee multiplier
                fee = (fee * resourceFeeMultipliers[resourceId]) / 1_000;
            }
        }
    }
}
