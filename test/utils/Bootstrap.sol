// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.20;

import {EntryPoint, UserOperation} from "lib/account-abstraction/contracts/core/EntryPoint.sol";
import {IEntryPoint} from "lib/account-abstraction/contracts/interfaces/IEntryPoint.sol";

import {MarginPaymaster, OptimismGoerliParameters, OptimismParameters, BaseParameters, Setup} from "script/Deploy.s.sol";
import {IPerpsMarketProxy} from "src/interfaces/external/IPerpsMarketProxy.sol";
import {IV3SwapRouter} from "src/interfaces/external/IV3SwapRouter.sol";
import {IWETH9} from "src/interfaces/external/IWETH9.sol";
import {AccountFactory, MockAccount} from "src/MockAccount.sol";
import {IUSDC} from "test/utils/interfaces/IUSDC.sol";
import {Test} from "lib/forge-std/src/Test.sol";
import {console} from "lib/forge-std/src/console.sol";

contract Bootstrap is Test {
    error SenderAddressResult(address sender);

    MarginPaymaster internal marginPaymaster;
    address payable internal marginPaymasterAddress;
    EntryPoint internal entryPoint;
    AccountFactory internal accountFactory;
    MockAccount internal account;
    uint256 backEndPk = 0x123;
    uint256 userPk = 0x1234;
    uint256 bundlerPk = 0x12345;
    address payable internal backEnd = payable(vm.addr(0x123));
    address payable internal user = payable(vm.addr(0x1234));
    address payable internal bundler = payable(vm.addr(0x12345));
    uint256 internal initialPaymasterBalance = 10 ether;
    address internal sender;
    address internal pool;

    UserOperation[] ops;

    /*//////////////////////////////////////////////////////////////
                        CHAIN SPECIFIC ADDRESSES
    //////////////////////////////////////////////////////////////*/

    address internal perpsMarketProxyAddress;
    IPerpsMarketProxy internal perpsMarketProxy;
    address internal spotMarketProxyAddress;
    address internal sUSDAddress;
    address internal pDAOAddress;
    address internal smartMarginV3Address;
    address payable internal canonicalEntryPointAddress;
    address internal usdcAddress;
    IUSDC internal usdc;
    uint128 internal sUSDCId;
    IV3SwapRouter internal uniV3Router;
    IWETH9 internal weth;

    function initializeLocal() internal {
        entryPoint = new EntryPoint();
        BootstrapLocal bootstrap = new BootstrapLocal();
        marginPaymasterAddress = bootstrap.init(
            address(entryPoint),
            address(0),
            address(0),
            address(0),
            address(0),
            address(0),
            0,
            address(0),
            address(0),
            address(0)
        );
        marginPaymaster = MarginPaymaster(marginPaymasterAddress);
    }

    function initializeBase() internal {
        BootstrapBase bootstrap = new BootstrapBase();
        (
            address payable _marginPaymasterAddress,
            address _perpsMarketProxyAddress,
            address _spotMarketProxyAddress,
            address _sUSDAddress,
            address _pDAOAddress,
            address _smartMarginV3Address,
            address _canonicalEntryPointAddress,
            address _usdc,
            uint128 _sUSDCId,
            address _uniswapRouter,
            address _weth,
            address _pool
        ) = bootstrap.init();
        perpsMarketProxyAddress = _perpsMarketProxyAddress;
        perpsMarketProxy = IPerpsMarketProxy(perpsMarketProxyAddress);
        spotMarketProxyAddress = _spotMarketProxyAddress;
        sUSDAddress = _sUSDAddress;
        pDAOAddress = _pDAOAddress;
        smartMarginV3Address = _smartMarginV3Address;
        canonicalEntryPointAddress = payable(_canonicalEntryPointAddress);
        entryPoint = EntryPoint(canonicalEntryPointAddress);
        usdcAddress = _usdc;
        usdc = IUSDC(usdcAddress);
        sUSDCId = _sUSDCId;
        uniV3Router = IV3SwapRouter(_uniswapRouter);
        weth = IWETH9(_weth);
        pool = _pool;

        marginPaymasterAddress = _marginPaymasterAddress;
        marginPaymaster = MarginPaymaster(marginPaymasterAddress);

        vm.prank(address(bootstrap));
        marginPaymaster.transferOwnership(address(this));
    }

    // function initializeOptimismGoerli() internal {
    //     BootstrapOptimismGoerli bootstrap = new BootstrapOptimismGoerli();
    //     marginPaymasterAddress = bootstrap.init();
    //     marginPaymaster = MarginPaymaster(marginPaymasterAddress);
    // }

    // function initializeOptimism() internal {
    //     BootstrapOptimismGoerli bootstrap = new BootstrapOptimismGoerli();
    //     marginPaymasterAddress = bootstrap.init();
    //     marginPaymaster = MarginPaymaster(marginPaymasterAddress);
    // }
}

contract BootstrapLocal is Setup {
    function init(
        address entryPoint,
        address smartMarginV3,
        address perpsMarketSNXV3,
        address usdc,
        address sUSDProxy,
        address spotMarketProxy,
        uint128 sUSDCId,
        address uniswapRouter,
        address weth,
        address pool
    ) public returns (address payable) {
        address payable marginPaymasterAddress = Setup.deploySystem(
            entryPoint,
            smartMarginV3,
            perpsMarketSNXV3,
            usdc,
            sUSDProxy,
            spotMarketProxy,
            sUSDCId,
            uniswapRouter,
            weth,
            pool
        );

        return marginPaymasterAddress;
    }
}

contract BootstrapBase is Setup, BaseParameters {
    function init()
        public
        returns (
            address payable,
            address,
            address,
            address,
            address,
            address,
            address,
            address,
            uint128,
            address,
            address,
            address
        )
    {
        address payable marginPaymasterAddress = Setup.deploySystem(
            CANONICAL_ENTRY_POINT,
            SMART_MARGIN_V3,
            PERPS_MARKET_PROXY_ANDROMEDA,
            USDC,
            USD_PROXY_ANDROMEDA,
            SPOT_MARKET_PROXY_ANDROMEDA,
            SUSDC_SPOT_MARKET_ID,
            UNISWAP_ROUTER_02,
            WETH,
            UNI_WETH_USDC_POOL
        );

        return (
            marginPaymasterAddress,
            PERPS_MARKET_PROXY_ANDROMEDA,
            SPOT_MARKET_PROXY_ANDROMEDA,
            USD_PROXY_ANDROMEDA,
            PDAO,
            SMART_MARGIN_V3,
            CANONICAL_ENTRY_POINT,
            USDC,
            SUSDC_SPOT_MARKET_ID,
            UNISWAP_ROUTER_02,
            WETH,
            UNI_WETH_USDC_POOL
        );
    }
}

// contract BootstrapOptimism is Setup, OptimismParameters {
//     function init() public returns (address) {
//         address marginPaymasterAddress = Setup.deploySystem();

//         return marginPaymasterAddress;
//     }
// }

// contract BootstrapOptimismGoerli is Setup, OptimismGoerliParameters {
//     function init() public returns (address) {
//         address marginPaymasterAddress = Setup.deploySystem();

//         return marginPaymasterAddress;
//     }
// }

// add other networks here as needed (ex: Base, BaseGoerli)
