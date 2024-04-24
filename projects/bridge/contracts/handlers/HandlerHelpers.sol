// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.11;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import "../interfaces/IERCHandler.sol";
import "../interfaces/IAccessControl.sol";

/**
    @title Function used across handler contracts.
    @author ChainSafe Systems.
    @notice This contract is intended to be used with the Bridge contract.
 */
abstract contract HandlerHelpers is IERCHandler {
    address public immutable _bridgeAddress;

    // resourceID => token contract address
    mapping(bytes32 => address) public _resourceIDToTokenContractAddress;

    // token contract address => resourceID
    mapping(address => bytes32) public _tokenContractAddressToResourceID;

    // token contract address => is whitelisted
    mapping(address => bool) public _contractWhitelist;

    modifier onlyBridge() {
        _onlyBridge();
        _;
    }

    modifier onlyBridgeAdmin() {
        _onlyBridgeAdmin();
        _;
    }

    /**
        @param bridgeAddress Contract address of previously deployed Bridge.
     */
    constructor(address bridgeAddress) {
        require(bridgeAddress != address(0));
        _bridgeAddress = bridgeAddress;
    }

    function _onlyBridge() private view {
        require(msg.sender == _bridgeAddress, "!Bridge");
    }

    function _onlyBridgeAdmin() private view {
        IAccessControl bridge = IAccessControl(_bridgeAddress);
        bool isBridgeAdmin = bridge.hasRole(bridge.DEFAULT_ADMIN_ROLE(), msg.sender);
        require(isBridgeAdmin, "!Bridge admin");
    }

    /**
        @notice sets {_resourceIDToContractAddress} with {contractAddress},
        {_tokenContractAddressToResourceID} with {resourceID},
        and {_contractWhitelist} to true for {contractAddress}.
        @param resourceID ResourceID to be used when making deposits.
        @param contractAddress Address of contract to be called when a deposit is made and a deposited is executed.
     */
    function setResource(bytes32 resourceID, address contractAddress) external override onlyBridge {
        _setResource(resourceID, contractAddress);
    }

    /**
        @notice stops resourceID from being handled by this handler.
        @param resourceID ResourceID that was used when making deposits.
     */
    function removeResource(bytes32 resourceID) external override onlyBridge {
        _removeResource(resourceID);
    }

    function withdraw(address tokenAddress, address recipient, uint256 amount) external onlyBridgeAdmin {
        if (tokenAddress == address(0)) {
            payable(recipient).transfer(amount);
        } else {
            // no need to use safeTransfer as this method is only used directly from admin
            IERC20(tokenAddress).transfer(recipient, amount);
        }
    }

    function _setResource(bytes32 resourceID, address contractAddress) internal virtual {
        _resourceIDToTokenContractAddress[resourceID] = contractAddress;
        _tokenContractAddressToResourceID[contractAddress] = resourceID;

        _contractWhitelist[contractAddress] = true;
    }

    function _removeResource(bytes32 resourceID) internal virtual {
        address contractAddress = _resourceIDToTokenContractAddress[resourceID];
        require(contractAddress != address(0), "invalid resourceID");
        _resourceIDToTokenContractAddress[resourceID] = address(0);
        _tokenContractAddressToResourceID[contractAddress] = bytes32(0);

        _contractWhitelist[contractAddress] = false;
    }
}
