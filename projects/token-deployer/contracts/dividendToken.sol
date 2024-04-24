// SPDX-License-Identifier: MIT

pragma solidity 0.8.17;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "./interfaces/IIceCreamSwapFactory.sol";
import "./interfaces/IIceCreamSwapRouter.sol";
import "./swapHelper.sol";

contract DividendToken is Ownable, IERC20 {
    //shares represent the token someone with reflections turned on has.

    //over time each share becomes worth more tokens so the tokens someone holds grow

    mapping(address => uint256) public Shares;

    //exFcluded from Reflection accounts just track the exact amount of tokens

    mapping(address => uint256) public ExcludedBalances;

    mapping(address => bool) public ExcludedFromReflection;

    mapping(address => bool) public ExcludedFromFees;

    mapping(address => mapping(address => uint256)) private _allowances;

    //Market makers have different Fees for Buy/Sell

    mapping(address => bool) public _isMarketMaker;

    uint256 _buyTax;

    uint256 _sellTax;

    uint256 _transferTax;

    //The taxes are split into different uses and need to add up to "TAX_DENOMINATOR"

    uint256 _marketingTax;

    uint256 _reflectionTax;

    uint256 _liquidityTax;

    uint256 _contractTax;

    //percentage of liquidity to be reached to trigger an auto liqudiity addition (500=5%)
    uint256 _swapTreshold;

    //Manual swap disables auto swap, should there be a problem

    bool _manualSwap;

    uint256 constant TAX_DENOMINATOR = 10000;

    //DividentMagnifier to make Reflection more accurate

    uint256 constant DividentMagnifier = 2 ** 128;

    uint256 TokensPerShare = DividentMagnifier;

    uint8 constant _decimals = 18;

    uint256 public maxWallet;

    mapping(address => bool) public _isMaxWalletExempt;

    uint256 _totalShares; //All non excluded tokens get tracked here as shares
    uint256 _totalExcludedTokens; //All excluded tokens get tracked here as tokens

    string public symbol;
    string public name;

    address public marketingWallet;
    address private dexPair;
    address private nativeDexPair;

    IERC20 private pairedToken;
    IIceCreamSwapRouter private dexRouter;
    SwapHelper private swapHelper;

    event onSetManualSwap(bool manual);

    event OnSetSwapTreshold(uint256 treshold);

    event OnSetAMM(address AMM, bool add);

    event OnSetTaxes(
        uint256 Buy,
        uint256 Sell,
        uint256 Transfer,
        uint256 Reflection,
        uint256 Liquidity,
        uint256 Marketing
    );

    event OnSetMaxWallet(uint256 _maxWallet);

    event OnSetMaxWalletExempt(address wallet, bool exempt);

    event OnSetExcludedFromFee(address account, bool exclude);

    event OnSetExcludedFromReflection(address account, bool exclude);

    event OnSetMarketingWallet(address wallet);

    event OnProlongLPLock(uint256 UnlockTimestamp);

    event OnReleaseLP();

    constructor(
        string memory _symbol,
        string memory _name,
        uint256 _supply, // supply in wei
        uint256 buyTax, // 100 = 1%
        uint256 sellTax, // 100 = 1%
        uint256 marketingTax, // marketingTax + reflectionTax + liquidityTax needs to be 10_000
        uint256 reflectionTax, // marketing tax goes to admin as ETH, reflection to all users as this token
        uint256 liquidityTax, // and liquidity tax gets provided as DEX liquidity 50% ETH 50% this token
        IERC20 _pairedToken,
        IIceCreamSwapRouter _dexRouter, // dex router address to list liquidity at
        address owner
    ) {
        symbol = _symbol;
        name = _name;

        setTaxes(buyTax, sellTax, 0, reflectionTax, liquidityTax, marketingTax);

        setSwapTreshold(100); // by default, swap when 1% of liquidity is accumulated as fees

        SetMaxWallet(_supply);

        dexRouter = _dexRouter;

        pairedToken = _pairedToken;

        dexPair = IIceCreamSwapFactory(_dexRouter.factory()).createPair(address(this), address(_pairedToken));
        nativeDexPair = IIceCreamSwapFactory(_dexRouter.factory()).createPair(address(this), _dexRouter.WETH());

        swapHelper = new SwapHelper(_dexRouter);

        _isMarketMaker[dexPair] = true;
        _isMarketMaker[nativeDexPair] = true;

        _isMaxWalletExempt[dexPair] = true;
        _isMaxWalletExempt[nativeDexPair] = true;
        _isMaxWalletExempt[address(swapHelper)] = true;

        //Pancake pair and contract never get reflections and can't be included
        _excludeFromReflection(address(this), true);
        _excludeFromReflection(dexPair, true);
        _excludeFromReflection(nativeDexPair, true);

        //Contract never pays fees and can't be included
        ExcludedFromFees[owner] = true;
        ExcludedFromFees[address(this)] = true;
        ExcludedFromFees[address(swapHelper)] = true;

        //marketing wallet is by default the owner
        marketingWallet = owner;

        // transfer owner
        transferOwnership(owner);

        // approve the dex router for this token and pairedToken
        _allowances[address(this)][address(dexRouter)] = type(uint256).max;
        _allowances[address(this)][address(swapHelper)] = type(uint256).max;
        pairedToken.approve(address(dexRouter), type(uint256).max);

        // mint initial supply and send to owner
        addTokens(owner, _supply);

        emit Transfer(address(0), owner, _supply);
    }

    ////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

    ///Transfer/////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

    ////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

    function _transfer(address sender, address recipient, uint256 amount) private {
        require(sender != address(0), "transfer from zero");

        require(recipient != address(0), "transfer to zero");

        require(amount > 0, "amount zero");

        if (ExcludedFromFees[sender] || ExcludedFromFees[recipient]) transferFeeless(sender, recipient, amount);
        else transferWithFee(sender, recipient, amount);
    }

    function transferFeeless(address sender, address recipient, uint256 amount) private {
        removeTokens(sender, amount);

        addTokens(recipient, amount);

        emit Transfer(sender, recipient, amount);
    }

    function transferWithFee(address sender, address recipient, uint256 amount) private {
        removeTokens(sender, amount);

        uint256 tax = _transferTax;
        if (_isMarketMaker[sender]) {
            // buy
            tax = _buyTax;
        } else if (_isMarketMaker[recipient]) {
            // sell
            tax = _sellTax;
        }

        uint256 TaxedAmount = (amount * tax) / TAX_DENOMINATOR;

        if (!_isMaxWalletExempt[recipient]) {
            require(balanceOf(recipient) + amount - TaxedAmount < maxWallet, "max Wallet");
        }

        uint256 ContractToken = (TaxedAmount * _contractTax) / TAX_DENOMINATOR;

        uint256 ReflectToken = TaxedAmount - ContractToken;

        if (ContractToken > 0) addTokens(address(this), ContractToken);

        if (ReflectToken > 0) reflectTokens(ReflectToken);

        if (!_isSwappingContractModifier && sender != dexPair && sender != nativeDexPair && !_manualSwap)
            _swapContractToken(false);

        addTokens(recipient, amount - TaxedAmount);

        emit Transfer(sender, recipient, amount - TaxedAmount);
        emit Transfer(sender, address(this), ContractToken);
        emit Transfer(sender, address(0), ReflectToken);
    }

    //Adds token respecting reflection
    function addTokens(address account, uint256 tokens) private {
        uint256 Balance = balanceOf(account);

        uint256 newBalance = Balance + tokens;

        if (ExcludedFromReflection[account]) {
            ExcludedBalances[account] = newBalance;

            _totalExcludedTokens += tokens;
        } else {
            uint256 oldShares = SharesFromTokens(Balance);

            uint256 newShares = SharesFromTokens(newBalance);

            Shares[account] = newShares;

            _totalShares += (newShares - oldShares);
        }
    }

    //Removes token respecting reflection

    function removeTokens(address account, uint256 tokens) private {
        uint256 Balance = balanceOf(account);

        require(tokens <= Balance, "Transfer exceeds Balance");

        uint256 newBalance = Balance - tokens;

        if (ExcludedFromReflection[account]) {
            ExcludedBalances[account] = newBalance;

            _totalExcludedTokens -= (Balance - newBalance);
        } else {
            uint256 oldShares = SharesFromTokens(Balance);

            uint256 newShares = SharesFromTokens(newBalance);

            Shares[account] = newShares;

            _totalShares -= (oldShares - newShares);
        }
    }

    //Handles reflection of already substracted token

    function reflectTokens(uint256 tokens) private {
        if (_totalShares == 0) return; //if total shares=0 reflection disappears into nothing

        TokensPerShare += (tokens * DividentMagnifier) / _totalShares;
    }

    function TokensFromShares(uint256 shares) public view returns (uint256) {
        return (shares * TokensPerShare) / DividentMagnifier;
    }

    function SharesFromTokens(uint256 tokens) public view returns (uint256) {
        return (tokens * DividentMagnifier) / TokensPerShare;
    }

    ////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

    ///SwapContractToken////////////////////////////////////////////////////////////////////////////////////////////////////////////////

    ////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

    bool private _isSwappingContractModifier;

    modifier lockTheSwap() {
        _isSwappingContractModifier = true;

        _;

        _isSwappingContractModifier = false;
    }

    function _swapContractToken(bool ignoreLimits) private lockTheSwap {
        if (_contractTax == 0) return;

        uint256 contractBalance = ExcludedBalances[address(this)];

        bool nativeBigger = false;
        uint256 tokenToSwap = (ExcludedBalances[dexPair] * _swapTreshold) / TAX_DENOMINATOR;
        {
            uint256 tokenToSwapNative = (ExcludedBalances[nativeDexPair] * _swapTreshold) / TAX_DENOMINATOR;
            if (tokenToSwapNative > tokenToSwap) {
                nativeBigger = true;
                tokenToSwap = tokenToSwapNative;
            }
        }

        if (ignoreLimits) {
            tokenToSwap = contractBalance;
        } else {
            if (contractBalance <= tokenToSwap) return;
        }

        //splits the token in TokenForLiquidity and tokenForMarketing
        uint256 tokenForLiquidity = (tokenToSwap * _liquidityTax) / _contractTax;
        uint256 tokenForMarketing = tokenToSwap - tokenForLiquidity;

        //splits tokenForLiquidity in 2 halves
        uint256 liqToken = tokenForLiquidity / 2;

        //swaps marketingToken and the liquidity token half for pairedToken
        uint256 swapToken = liqToken + tokenForMarketing;

        if (swapToken == 0) return;

        swapHelper.swapToken(swapToken, nativeBigger, address(pairedToken));

        uint256 newPairedToken = pairedToken.balanceOf(address(this));

        //calculates the amount of paired token belonging to the LP-Pair and converts them to LP

        uint256 liqPairedToken = (newPairedToken * liqToken) / swapToken;

        if (liqPairedToken > 0) _addLiquidity(liqToken, liqPairedToken);

        pairedToken.transfer(marketingWallet, pairedToken.balanceOf(address(this)));
    }

    function _addLiquidity(uint256 tokenAmount, uint256 pairedTokenAmount) private {
        dexRouter.addLiquidity(
            address(this),
            address(pairedToken),
            tokenAmount,
            pairedTokenAmount,
            0,
            0,
            address(this),
            block.timestamp
        );
    }

    ////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

    ///Settings/////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

    ////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

    function ReflectTokens(uint256 amount) external {
        removeTokens(msg.sender, amount);

        reflectTokens(amount);

        emit Transfer(msg.sender, address(0), amount);
    }

    function SetMaxWallet(uint256 _maxWallet) public onlyOwner {
        require(_maxWallet >= totalSupply() / 1000, "<0.1%");
        maxWallet = _maxWallet;
        emit OnSetMaxWallet(_maxWallet);
    }

    function swapContractToken() external onlyOwner {
        _swapContractToken(true);
    }

    function setManualSwap(bool manual) external onlyOwner {
        _manualSwap = manual;

        emit onSetManualSwap(manual);
    }

    function setSwapTreshold(uint256 treshold) public onlyOwner {
        require(treshold <= TAX_DENOMINATOR / 10, ">10%");

        _swapTreshold = treshold;

        emit OnSetSwapTreshold(treshold);
    }

    function setAMM(address AMM, bool add) external onlyOwner {
        require(AMM != dexPair && AMM != nativeDexPair, "!dexPair");

        _isMarketMaker[AMM] = add;
        _isMaxWalletExempt[AMM] = add;

        emit OnSetAMM(AMM, add);
    }

    function setMaxWalletExempt(address wallet, bool exempt) external onlyOwner {
        require(wallet != dexPair && wallet != nativeDexPair, "!dexPair");

        _isMaxWalletExempt[wallet] = exempt;

        emit OnSetMaxWalletExempt(wallet, exempt);
    }

    function setTaxes(
        uint256 Buy,
        uint256 Sell,
        uint256 Transfer,
        uint256 Reflection,
        uint256 Liquidity,
        uint256 Marketing
    ) public onlyOwner {
        uint256 maxTax = TAX_DENOMINATOR / 10; //10% max tax

        require(Buy <= maxTax && Sell <= maxTax && Transfer <= maxTax, "max 10% Tax");
        require(Sell <= Buy * 2, "sell tax > 2x buy tax");

        require(Reflection + Liquidity + Marketing == TAX_DENOMINATOR, "sum(taxes) != TAX_DENOMINATOR");
        require(Marketing <= TAX_DENOMINATOR / 2, "marketing max 50%");

        _buyTax = Buy;

        _sellTax = Sell;

        _transferTax = Transfer;

        _reflectionTax = Reflection;

        _liquidityTax = Liquidity;

        _marketingTax = Marketing;

        _contractTax = TAX_DENOMINATOR - _reflectionTax;

        emit OnSetTaxes(Buy, Sell, Transfer, Reflection, Liquidity, Marketing);
    }

    function setExcludedFromFee(address account, bool exclude) public onlyOwner {
        require(account != address(this), "!self");

        ExcludedFromFees[account] = exclude;

        emit OnSetExcludedFromFee(account, exclude);
    }

    function setExcludedFromReflection(address account, bool exclude) public onlyOwner {
        //Contract and PancakePair never can receive reflections

        require(
            account != address(this) && account != dexPair && account != nativeDexPair && account != address(0xdead),
            "can not exclude address"
        );

        _excludeFromReflection(account, exclude);

        emit OnSetExcludedFromReflection(account, exclude);
    }

    function _excludeFromReflection(address account, bool exclude) private {
        require(ExcludedFromReflection[account] != exclude, "already set");

        uint256 tokens = balanceOf(account);

        ExcludedFromReflection[account] = exclude;

        if (exclude) {
            uint256 shares = Shares[account];

            _totalShares -= shares;

            Shares[account] = 0;

            ExcludedBalances[account] = tokens;

            _totalExcludedTokens += tokens;
        } else {
            ExcludedBalances[account] = 0;

            _totalExcludedTokens -= tokens;

            uint256 shares = SharesFromTokens(tokens);

            Shares[account] = shares;

            _totalShares += shares;
        }
    }

    function SetMarketingWallet(address newMarketingWallet) public onlyOwner {
        marketingWallet = newMarketingWallet;

        emit OnSetMarketingWallet(newMarketingWallet);
    }

    ////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

    ///View/////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

    ////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

    function getTaxes()
        public
        view
        returns (uint256 Buy, uint256 Sell, uint256 Transfer, uint256 Reflection, uint256 LP, uint256 Marketing)
    {
        Buy = _buyTax;

        Sell = _sellTax;

        Transfer = _transferTax;

        Reflection = _reflectionTax;

        LP = _liquidityTax;

        Marketing = _marketingTax;
    }

    function getInfo()
        public
        view
        returns (uint256 SwapTreshold, uint256 TotalShares, uint256 TotalExcluded, bool ManualSwap)
    {
        SwapTreshold = _swapTreshold;

        TotalExcluded = _totalExcludedTokens;

        TotalShares = _totalShares;

        ManualSwap = _manualSwap;
    }

    ////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

    ///Liquidity Lock///////////////////////////////////////////////////////////////////////////////////////////////////////////////////

    ////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

    function RescueTokens(address token) public onlyOwner {
        require(token != address(this) && token != dexPair && token != nativeDexPair, "no draining");

        IERC20(token).transfer(msg.sender, IERC20(token).balanceOf(address(this)));
    }

    ////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

    ///BEP20 Implementation/////////////////////////////////////////////////////////////////////////////////////////////////////////////

    ////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

    receive() external payable {}

    function decimals() external pure returns (uint8) {
        return _decimals;
    }

    function balanceOf(address account) public view override returns (uint256) {
        if (ExcludedFromReflection[account]) return ExcludedBalances[account];

        return TokensFromShares(Shares[account]);
    }

    function totalSupply() public view override returns (uint256) {
        return _totalExcludedTokens + TokensFromShares(_totalShares);
    }

    function allowance(address _owner, address spender) external view override returns (uint256) {
        return _allowances[_owner][spender];
    }

    function approve(address spender, uint256 amount) external override returns (bool) {
        _approve(msg.sender, spender, amount);

        return true;
    }

    function _approve(address owner, address spender, uint256 amount) private {
        require(owner != address(0) && spender != address(0), "!zero address");

        _allowances[owner][spender] = amount;

        emit Approval(owner, spender, amount);
    }

    function transfer(address recipient, uint256 amount) external override returns (bool) {
        _transfer(msg.sender, recipient, amount);

        return true;
    }

    function transferFrom(address sender, address recipient, uint256 amount) external override returns (bool) {
        _transfer(sender, recipient, amount);

        uint256 currentAllowance = _allowances[sender][msg.sender];

        if (currentAllowance != type(uint256).max) {
            require(currentAllowance >= amount, "Transfer exceeds allowance");
            _approve(sender, msg.sender, currentAllowance - amount);
        }

        return true;
    }

    function increaseAllowance(address spender, uint256 addedValue) external returns (bool) {
        _approve(msg.sender, spender, _allowances[msg.sender][spender] + addedValue);

        return true;
    }

    function decreaseAllowance(address spender, uint256 subtractedValue) external returns (bool) {
        uint256 currentAllowance = _allowances[msg.sender][spender];

        require(currentAllowance >= subtractedValue, "exceeds allowance");

        _approve(msg.sender, spender, currentAllowance - subtractedValue);

        return true;
    }

    function burn(uint256 amount) external {
        removeTokens(msg.sender, amount);
        emit Transfer(msg.sender, address(0), amount);
    }

    function burnFrom(address account, uint256 amount) external virtual {
        uint256 currentAllowance = _allowances[account][msg.sender];
        require(currentAllowance >= amount, "Transfer exceeds allowance");
        _approve(account, msg.sender, currentAllowance - amount);

        removeTokens(account, amount);
        emit Transfer(account, address(0), amount);
    }
}
