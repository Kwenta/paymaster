// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.25;

import {EntryPoint, UserOperation} from "lib/account-abstraction/contracts/core/EntryPoint.sol";
import {IEntryPoint} from "lib/account-abstraction/contracts/interfaces/IEntryPoint.sol";

import {MarginPaymaster, OptimismGoerliParameters, OptimismParameters, BaseParameters, Setup} from "script/Deploy.s.sol";
import {AccountFactory, Account} from "src/Account.sol";
import {Test} from "lib/forge-std/src/Test.sol";
import {console} from "lib/forge-std/src/console.sol";

contract Bootstrap is Test {
    error SenderAddressResult(address sender);

    MarginPaymaster internal marginPaymaster;
    address internal marginPaymasterAddress;
    EntryPoint internal entryPoint;
    AccountFactory internal accountFactory;
    Account internal account;
    uint256 userPk = 0x1234;
    uint256 bundlerPk = 0x12345;
    address payable user = payable(vm.addr(0x1234));
    address payable bundler = payable(vm.addr(0x12345));
    uint256 internal initialPaymasterBalance = 10 ether;
    address internal sender;

    UserOperation[] ops;

    /*//////////////////////////////////////////////////////////////
                        CHAIN SPECIFIC ADDRESSES
    //////////////////////////////////////////////////////////////*/

    address internal perpsMarketProxyAddress;
    address internal spotMarketProxyAddress;
    address internal sUSDAddress;
    address internal pDAOAddress;
    address internal smartMarginV3Address;
    address payable internal canonicalEntryPointAddress;
    address internal usdc;
    uint128 internal sUSDCId;

    function initializeLocal() internal {
        BootstrapLocal bootstrap = new BootstrapLocal();
        marginPaymasterAddress = bootstrap.init();
        marginPaymaster = MarginPaymaster(marginPaymasterAddress);
    }

    function initializeOptimismGoerli() internal {
        BootstrapOptimismGoerli bootstrap = new BootstrapOptimismGoerli();
        marginPaymasterAddress = bootstrap.init();
        marginPaymaster = MarginPaymaster(marginPaymasterAddress);
    }

    function initializeOptimism() internal {
        BootstrapOptimismGoerli bootstrap = new BootstrapOptimismGoerli();
        marginPaymasterAddress = bootstrap.init();
        marginPaymaster = MarginPaymaster(marginPaymasterAddress);
    }

    function initializeBase() internal {
        BootstrapBase bootstrap = new BootstrapBase();
        (
            address _marginPaymasterAddress,
            address _perpsMarketProxyAddress,
            address _spotMarketProxyAddress,
            address _sUSDAddress,
            address _pDAOAddress,
            address _smartMarginV3Address,
            address _canonicalEntryPointAddress,
            address _usdc,
            uint128 _sUSDCId
        ) = bootstrap.init();
        perpsMarketProxyAddress = _perpsMarketProxyAddress;
        spotMarketProxyAddress = _spotMarketProxyAddress;
        sUSDAddress = _sUSDAddress;
        pDAOAddress = _pDAOAddress;
        smartMarginV3Address = _smartMarginV3Address;
        canonicalEntryPointAddress = payable(_canonicalEntryPointAddress);
        usdc = _usdc;
        sUSDCId = _sUSDCId;

        marginPaymasterAddress = _marginPaymasterAddress;
        marginPaymaster = MarginPaymaster(marginPaymasterAddress);
    }

    /// @dev add other networks here as needed (ex: Base, BaseGoerli)
}

contract BootstrapLocal is Setup {
    function init() public returns (address) {
        address marginPaymasterAddress = Setup.deploySystem();

        return marginPaymasterAddress;
    }
}

contract BootstrapOptimism is Setup, OptimismParameters {
    function init() public returns (address) {
        address marginPaymasterAddress = Setup.deploySystem();

        return marginPaymasterAddress;
    }
}

contract BootstrapOptimismGoerli is Setup, OptimismGoerliParameters {
    function init() public returns (address) {
        address marginPaymasterAddress = Setup.deploySystem();

        return marginPaymasterAddress;
    }
}

contract BootstrapBase is Setup, BaseParameters {
    function init() public returns (
            address,
            address,
            address,
            address,
            address,
            address,
            address,
            address,
            uint128
    ) {
        address marginPaymasterAddress = Setup.deploySystem();

        return (
            marginPaymasterAddress,
            PERPS_MARKET_PROXY_ANDROMEDA,
            SPOT_MARKET_PROXY_ANDROMEDA,
            USD_PROXY_ANDROMEDA,
            PDAO,
            SMART_MARGIN_V3,
            CANONICAL_ENTRY_POINT,
            USDC,
            SUSDC_SPOT_MARKET_ID
        );
    }
}

// add other networks here as needed (ex: Base, BaseGoerli)
