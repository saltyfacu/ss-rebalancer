// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.18;
import "forge-std/console.sol";

import {BaseTokenizedStrategy} from "@tokenized-strategy/BaseTokenizedStrategy.sol";

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {UniswapV3Swapper} from "@periphery/swappers/UniswapV3Swapper.sol";

import {IPearlRouter} from "./interfaces/PearlFi/IPearlRouter.sol";
import {IPair} from "./interfaces/PearlFi/IPair.sol";
import {IRewardPool} from "./interfaces/PearlFi/IRewardPool.sol";

import {IUSDRExchange} from "./interfaces/Tangible/IUSDRExchange.sol";
import {IQuoterV2} from "./interfaces/UniswapV3/IQuoterV2.sol";
import {IUniswapV3Factory} from "./interfaces/UniswapV3/IUniswapV3Factory.sol";
import {IUniswapV3Pool} from "./interfaces/UniswapV3/IUniswapV3Pool.sol";

import {IStableSwapPool} from "./interfaces/Synapse/IStableSwapPool.sol";

// Import interfaces for many popular DeFi projects, or add your own!
//import "../interfaces/<protocol>/<Interface>.sol";

/**
 * The `TokenizedStrategy` variable can be used to retrieve the strategies
 * specifc storage data your contract.
 *
 *       i.e. uint256 totalAssets = TokenizedStrategy.totalAssets()
 *
 * This can not be used for write functions. Any TokenizedStrategy
 * variables that need to be udpated post deployement will need to
 * come from an external call from the strategies specific `management`.
 */

// NOTE: To implement permissioned functions you can use the onlyManagement and onlyKeepers modifiers

contract Strategy is BaseTokenizedStrategy, UniswapV3Swapper {
    using SafeERC20 for ERC20;

    IUSDRExchange usdrExchange = IUSDRExchange(0x195F7B233947d51F4C3b756ad41a5Ddb34cEBCe0);
    IPearlRouter pearlRouter = IPearlRouter(0x06374F57991CDc836E5A318569A910FE6456D230);
    IPair lpToken;
    IRewardPool pearlRewards = IRewardPool(0x97Bd59A8202F8263C2eC39cf6cF6B438D0B45876);
    IQuoterV2 uniQuoter = IQuoterV2(0x61fFE014bA17989E743c5F6cB21bF9697530B21e);
    IUniswapV3Factory uniFactory = IUniswapV3Factory(0x1F98431c8aD98523631AE4a59f267346ea31F984);
    IStableSwapPool synapseStablePool = IStableSwapPool(0x85fCD7Dd0a1e1A9FCD5FD886ED522dE8221C3EE5);

    address public constant usdr = 0x40379a439D4F6795B6fc9aa5687dB461677A2dBa;
    address public constant pearl = 0x7238390d5f6F64e67c3211C343A410E2A3DEc142;
    

    constructor(
        address _asset,
        string memory _name
    ) BaseTokenizedStrategy(_asset, _name) {
        
        lpToken = IPair(pearlRouter.pairFor(usdr, asset, true));

        ERC20(asset).safeApprove(address(router), type(uint256).max);
        ERC20(asset).safeApprove(address(pearlRouter), type(uint256).max);
        ERC20(asset).safeApprove(address(usdrExchange), type(uint256).max);
        ERC20(asset).safeApprove(address(synapseStablePool), type(uint256).max);

        ERC20(usdr).safeApprove(address(pearlRouter), type(uint256).max);
        ERC20(usdr).safeApprove(address(usdrExchange), type(uint256).max);
        ERC20(pearl).safeApprove(address(pearlRouter), type(uint256).max);

        ERC20(address(lpToken)).safeApprove(address(pearlRewards), type(uint256).max);
        ERC20(address(lpToken)).safeApprove(address(pearlRouter), type(uint256).max);

    }

    /*//////////////////////////////////////////////////////////////
                NEEDED TO BE OVERRIDEN BY STRATEGIST
    //////////////////////////////////////////////////////////////*/

    /**
     * @dev Should deploy up to '_amount' of 'asset' in the yield source.
     *
     * This function is called at the end of a {deposit} or {mint}
     * call. Meaning that unless a whitelist is implemented it will
     * be entirely permsionless and thus can be sandwhiched or otherwise
     * manipulated.
     *
     * @param _amount The amount of 'asset' that the strategy should attemppt
     * to deposit in the yield source.
     */
    function _deployFunds(uint256 _amount) internal override {
        console.log("D1. Deploy: %s", _amount );
        console.log("D1.1. lpToken: %s", address(lpToken) );
        
        // get the ratio an amount we need of each
        ( uint256 lpBalanceOfUsdr, uint256 lpBalanceOfAsset, ) = lpToken.getReserves();
        console.log("D1.5 lpBalanceOfUsdr: %s, lpBalanceOfAsset: %s", _toEighteen(usdr, lpBalanceOfUsdr), _toEighteen(asset, lpBalanceOfAsset));
        
        uint256 usdrNeeded = _toEighteen(asset, _amount) * _toEighteen(usdr, lpBalanceOfUsdr) / (_toEighteen(asset, lpBalanceOfAsset) + _toEighteen(usdr, lpBalanceOfUsdr));
        console.log("D2. usdrNeeded: %s", usdrNeeded );

        (uint256 usdrToSwap, uint256 assetToDeposit, ) = pearlRouter.quoteAddLiquidity(
            usdr,
            asset,
            true,
            usdrNeeded/1e9,
            ERC20(asset).balanceOf(address(this))
        );

        console.log("D2.1. usdrToSwap adj: %s", usdrToSwap );

        uint256 usdrBalance = ERC20(usdr).balanceOf(address(this));

        if (usdrBalance < usdrNeeded) {
            usdrNeeded = usdrNeeded - usdrBalance;

            // 1 USDR = 1 DAI
            // deposit DAI in tangible

            console.log("D3. DAI in strat: %s", ERC20(asset).balanceOf(address(this)));
            usdrExchange.swapFromUnderlying(_toEighteen(usdr, usdrToSwap), address(this));
            console.log("D4. USDR swapped: %s, usdrNeeded: %s, DAI in the strat: %s", ERC20(usdr).balanceOf(address(this)), usdrToSwap, ERC20(asset).balanceOf(address(this)) );
            //TODO check that what I get in return is ok?
        }

        // add liquidity to pair
        pearlRouter.addLiquidity(
            lpToken.token0(), 
            lpToken.token1(), 
            lpToken.stable(), 
            ERC20(lpToken.token0()).balanceOf(address(this)),
            assetToDeposit,
            1, 1,
            address(this), 
            block.timestamp
        );

        // stake it 
        pearlRewards.deposit(lpToken.balanceOf(address(this)));

        console.log("D6. Loose amount: %d", ERC20(asset).balanceOf(address(this)) );

    }

    function _toEighteen(address _token, uint256 _amount) internal view returns (uint256) {
        return  _amount * (10 ** (18 - ERC20(_token).decimals()));
    }

    function _toNine(address _token, uint256 _amount) internal view returns (uint256 converted_amount) {
        uint256 token_decimals = ERC20(_token).decimals();

        if (token_decimals > 9) {
            converted_amount = _amount / (10 ** (ERC20(_token).decimals() - 9));
        } else {
            converted_amount = _amount * (10 ** (9 - ERC20(_token).decimals()));
        }
    }

    /**
     * @dev Will attempt to free the '_amount' of 'asset'.
     *
     * The amount of 'asset' that is already loose has already
     * been accounted for.
     *
     * This function is called during {withdraw} and {redeem} calls.
     * Meaning that unless a whitelist is implemented it will be
     * entirely permsionless and thus can be sandwhiched or otherwise
     * manipulated.
     *
     * Should not rely on asset.balanceOf(address(this)) calls other than
     * for diff accounting puroposes.
     *
     * Any difference between `_amount` and what is actually freed will be
     * counted as a loss and passed on to the withdrawer. This means
     * care should be taken in times of illiquidity. It may be better to revert
     * if withdraws are simply illiquid so not to realize incorrect losses.
     *
     * @param _amount, The amount of 'asset' to be freed.
     */
    function _freeFunds(uint256 _amount) internal override { 
        // TODO: min between balance and amount asked?
        if (_amount > 0) {
            console.log("F0. Amount to withdraw: %s", _amount);
                        
            uint256 lpsToWithdraw = _assetToLpTokens(_amount);
            uint256 lpsStaked = pearlRewards.balanceOf(address(this));

            console.log("F1. LPs to withdraw: %s", lpsToWithdraw);
            console.log("F1.5. LPs staked before withdraw: %d", lpsStaked);

            //if they ask for more than we have... we have what we have
            lpsToWithdraw = lpsToWithdraw > lpsStaked ? lpsStaked : lpsToWithdraw;
            
            pearlRewards.withdraw(lpsToWithdraw);

            console.log("F2. LPs staked after withdraw: %d", pearlRewards.balanceOf(address(this)));

            console.log("F3. balance of LPs in strat: %s", lpToken.balanceOf(address(this)));
            console.log("F4. balance of USDR in strat: %s", ERC20(usdr).balanceOf(address(this)));     
            console.log("F5. balance of DAI in strat: %s", ERC20(asset).balanceOf(address(this)));     
            pearlRouter.removeLiquidity(
                lpToken.token0(), 
                lpToken.token1(), 
                lpToken.stable(), 
                ERC20(address(lpToken)).balanceOf(address(this)),
                0, 0,
                address(this), 
                block.timestamp
            );
            
            console.log("After remove liquidity");
            console.log("F6. balance of LPs in strat: %s", lpToken.balanceOf(address(this)));
            console.log("F7. balance of USDR in strat: %s", ERC20(usdr).balanceOf(address(this)));
            console.log("F8. balance of DAI in strat: %s", ERC20(asset).balanceOf(address(this)));                 

            usdrExchange.swapToUnderlying(ERC20(usdr).balanceOf(address(this)), address(this)); //usdr-->dai
            console.log("After swap from USDR");
            console.log("F9. balance of LPs in strat: %s", lpToken.balanceOf(address(this)));
            console.log("F10. balance of USDR in strat: %s", ERC20(usdr).balanceOf(address(this)));
            console.log("F11. balance of DAI in strat: %s", ERC20(asset).balanceOf(address(this)));
        }
    }

    /**
     * @dev Internal function to harvest all rewards, redeploy any idle
     * funds and return an accurate accounting of all funds currently
     * held by the Strategy.
     *
     * This should do any needed harvesting, rewards selling, accrual,
     * redepositing etc. to get the most accurate view of current assets.
     *
     * NOTE: All applicable assets including loose assets should be
     * accounted for in this function.
     *
     * Care should be taken when relying on oracles or swap values rather
     * than actual amounts as all Strategy profit/loss accounting will
     * be done based on this returned value.
     *
     * This can still be called post a shutdown, a strategist can check
     * `TokenizedStrategy.isShutdown()` to decide if funds should be
     * redeployed or simply realize any profits/losses.
     *
     * @return _totalAssets A trusted and accurate account for the total
     * amount of 'asset' the strategy currently holds including idle funds.
     */
    function _harvestAndReport()
        internal
        override
        returns (uint256 _totalAssets)
    {
        if (!TokenizedStrategy.isShutdown()) {
                _claimAndSellRewards();

            // TODO: deposit loose funds
        }

        (uint256 amountUsdr, uint256 amountAsset) =_balanceOfUnderlying(_lpTokensFullBalance());

        _totalAssets = ERC20(asset).balanceOf(address(this)) + amountAsset + _usdrToAsset(amountUsdr);
    }
    
    function _claimAndSellRewards() internal 
    {        
        // claim lp fees 
        lpToken.claimFees();
        
        // get PEARL, sell them for asset 
        pearlRewards.getReward();
        uint256 pearlBalance = ERC20(pearl).balanceOf(address(this));

        console.log("C1. PEARL balance: %s", pearlBalance);
        
        if (pearlBalance > 0) {
            IPearlRouter.route memory pearlToUsdr = IPearlRouter.route(
                pearl,
                usdr,
                false
            );
            IPearlRouter.route memory usdrToAsset = IPearlRouter.route(
                usdr,
                asset,
                true
            );
            
            IPearlRouter.route[] memory routes = new IPearlRouter.route[](2);
            routes[0] = pearlToUsdr;
            routes[1] = usdrToAsset;
            
            pearlRouter.swapExactTokensForTokens(
                ERC20(pearl).balanceOf(address(this)),
                0,
                routes,
                address(this),
                block.timestamp
            );
        }

        console.log("C2. PEARL balance: %s", ERC20(pearl).balanceOf(address(this)));
        console.log("C3. DAI balance: %s", ERC20(asset).balanceOf(address(this)));

    }

    function _balanceOfUnderlying(uint256 _amount) 
        internal 
        returns(uint256 amountUsdr, uint256 amountAsset) 
    {
        (amountUsdr, amountAsset) = pearlRouter.quoteRemoveLiquidity(
            usdr,
            asset,
            true, //stable pool 
            _amount
        );

    }

    function _usdrToAsset(uint256 _amount) internal view returns (uint256)
    {
       return lpToken.getAmountOut(_toEighteen(usdr, _amount), asset);

    }

    function _assetToLpTokens(uint256 _amount) internal returns (uint256)
    {
        console.log("ATLP1. _amount: %s", _amount);
        // Amount of asset and USDR in 1 LP token
        (uint256 amountUsdr, uint256 amountAsset) = _balanceOfUnderlying(1e18);
        console.log("ATLP2. amountUsdr: %s, amountAsset: %s", amountUsdr, amountAsset);

        // amount of "asset" in 1 LP token
        uint256 usdrToAsset = _usdrToAsset(amountUsdr);
        uint256 amountOfAssetInLp = amountAsset + usdrToAsset;
        console.log("ATLP3. usdrToAsset: %s, amountAsset: %s", usdrToAsset, amountAsset);
        
        // need to scale amount to lp decimals, because amount of assets in lp is in asset decimals
        return (_amount*1e18/amountOfAssetInLp);

    }

    function _lpTokensFullBalance() internal view returns (uint256) 
    {
        return lpToken.balanceOf(address(this)) + pearlRewards.balanceOf(address(this));
    }

    /*//////////////////////////////////////////////////////////////
                    OPTIONAL TO OVERRIDE BY STRATEGIST
    //////////////////////////////////////////////////////////////*/

    /**
     * @dev Optional function for strategist to override that can
     *  be called in between reports.
     *
     * If '_tend' is used tendTrigger() will also need to be overridden.
     *
     * This call can only be called by a persionned role so may be
     * through protected relays.
     *
     * This can be used to harvest and compound rewards, deposit idle funds,
     * perform needed poisition maintence or anything else that doesn't need
     * a full report for.
     *
     *   EX: A strategy that can not deposit funds without getting
     *       sandwhiched can use the tend when a certain threshold
     *       of idle to totalAssets has been reached.
     *
     * The TokenizedStrategy contract will do all needed debt and idle updates
     * after this has finished and will have no effect on PPS of the strategy
     * till report() is called.
     *
     * @param _totalIdle The current amount of idle funds that are available to deploy.
     *
    function _tend(uint256 _totalIdle) internal override {}
    */

    /**
     * @notice Returns wether or not tend() should be called by a keeper.
     * @dev Optional trigger to override if tend() will be used by the strategy.
     * This must be implemented if the strategy hopes to invoke _tend().
     *
     * @return . Should return true if tend() should be called by keeper or false if not.
     *
    function tendTrigger() public view override returns (bool) {}
    */

    /**
     * @notice Gets the max amount of `asset` that an adress can deposit.
     * @dev Defaults to an unlimited amount for any address. But can
     * be overriden by strategists.
     *
     * This function will be called before any deposit or mints to enforce
     * any limits desired by the strategist. This can be used for either a
     * traditional deposit limit or for implementing a whitelist etc.
     *
     *   EX:
     *      if(isAllowed[_owner]) return super.availableDepositLimit(_owner);
     *
     * This does not need to take into account any conversion rates
     * from shares to assets. But should know that any non max uint256
     * amounts may be converted to shares. So it is recommended to keep
     * custom amounts low enough as not to cause overflow when multiplied
     * by `totalSupply`.
     *
     * @param . The address that is depositing into the strategy.
     * @return . The avialable amount the `_owner` can deposit in terms of `asset`
     *
    function availableDepositLimit(
        address _owner
    ) public view override returns (uint256) {
        TODO: If desired Implement deposit limit logic and any needed state variables .
        
        EX:    
            uint256 totalAssets = TokenizedStrategy.totalAssets();
            return totalAssets >= depositLimit ? 0 : depositLimit - totalAssets;
    }
    */

    /**
     * @notice Gets the max amount of `asset` that can be withdrawn.
     * @dev Defaults to an unlimited amount for any address. But can
     * be overriden by strategists.
     *
     * This function will be called before any withdraw or redeem to enforce
     * any limits desired by the strategist. This can be used for illiquid
     * or sandwhichable strategies. It should never be lower than `totalIdle`.
     *
     *   EX:
     *       return TokenIzedStrategy.totalIdle();
     *
     * This does not need to take into account the `_owner`'s share balance
     * or conversion rates from shares to assets.
     *
     * @param . The address that is withdrawing from the strategy.
     * @return . The avialable amount that can be withdrawn in terms of `asset`
     *
    function availableWithdrawLimit(
        address _owner
    ) public view override returns (uint256) {
        TODO: If desired Implement withdraw limit logic and any needed state variables.
        
        EX:    
            return TokenizedStrategy.totalIdle();
    }
    */

    /**
     * @dev Optional function for a strategist to override that will
     * allow management to manually withdraw deployed funds from the
     * yield source if a strategy is shutdown.
     *
     * This should attempt to free `_amount`, noting that `_amount` may
     * be more than is currently deployed.
     *
     * NOTE: This will not realize any profits or losses. A seperate
     * {report} will be needed in order to record any profit/loss. If
     * a report may need to be called after a shutdown it is important
     * to check if the strategy is shutdown during {_harvestAndReport}
     * so that it does not simply re-deploy all funds that had been freed.
     *
     * EX:
     *   if(freeAsset > 0 && !TokenizedStrategy.isShutdown()) {
     *       depositFunds...
     *    }
     *
     * @param _amount The amount of asset to attempt to free.
     *
    function _emergencyWithdraw(uint256 _amount) internal override {
        TODO: If desired implement simple logic to free deployed funds.

        EX:
            _amount = min(_amount, atoken.balanceOf(address(this)));
            lendingPool.withdraw(asset, _amount);
    }

    */
}
