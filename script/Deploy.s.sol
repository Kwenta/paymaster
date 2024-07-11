// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.20;

import {BaseGoerliParameters} from "script/utils/parameters/BaseGoerliParameters.sol";
import {BaseParameters} from "script/utils/parameters/BaseParameters.sol";
import {OptimismGoerliParameters} from "script/utils/parameters/OptimismGoerliParameters.sol";
import {OptimismParameters} from "script/utils/parameters/OptimismParameters.sol";
import {Script} from "lib/forge-std/src/Script.sol";
import {MarginPaymaster} from "src/MarginPaymaster.sol";

/// @title Kwenta deployment script
/// @author tommyrharper (zeroknowledgeltd@gmail.com)
/// @author JaredBorders (jaredborders@pm.me)
contract Setup is Script {
    function deploySystem(
        address entryPoint,
        address perpsMarketSNXV3,
        address usdc,
        address sUSDProxy,
        address spotMarketProxy,
        uint128 sUSDCId,
        address uniV3Router,
        address weth,
        address pool
    ) public returns (address payable) {
        MarginPaymaster marginPaymaster = new MarginPaymaster(
            entryPoint,
            perpsMarketSNXV3,
            usdc,
            sUSDProxy,
            spotMarketProxy,
            sUSDCId,
            uniV3Router,
            weth,
            pool
        );
        return payable(address(marginPaymaster));
    }
}

/// @dev steps to deploy and verify on Base:
/// (1) load the variables in the .env file via `source .env`
/// (2) run `forge script script/Deploy.s.sol:DeployBase --rpc-url $BASE_RPC_URL --etherscan-api-key $BASESCAN_API_KEY --broadcast --verify -vvvv`
contract DeployBase is Setup, BaseParameters {
    function run() public {
        uint256 privateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(privateKey);

        Setup.deploySystem(
            CANONICAL_ENTRY_POINT,
            PERPS_MARKET_PROXY_ANDROMEDA,
            USDC,
            USD_PROXY_ANDROMEDA,
            SPOT_MARKET_PROXY_ANDROMEDA,
            SUSDC_SPOT_MARKET_ID,
            UNISWAP_ROUTER_02,
            WETH,
            UNI_WETH_USDC_POOL
        );

        vm.stopBroadcast();
    }
}

// /// @dev steps to deploy and verify on Base Goerli:
// /// (1) load the variables in the .env file via `source .env`
// /// (2) run `forge script script/Deploy.s.sol:DeployBaseGoerli --rpc-url $BASE_GOERLI_RPC_URL --etherscan-api-key $BASESCAN_API_KEY --broadcast --verify -vvvv`
// contract DeployBaseGoerli is Setup, BaseGoerliParameters {
//     function run() public {
//         uint256 privateKey = vm.envUint("PRIVATE_KEY");
//         vm.startBroadcast(privateKey);

//         Setup.deploySystem();

//         vm.stopBroadcast();
//     }
// }

// /// @dev steps to deploy and verify on Optimism:
// /// (1) load the variables in the .env file via `source .env`
// /// (2) run `forge script script/Deploy.s.sol:DeployOptimism --rpc-url $OPTIMISM_RPC_URL --etherscan-api-key $OPTIMISM_ETHERSCAN_API_KEY --broadcast --verify -vvvv`
// contract DeployOptimism is Setup, OptimismParameters {
//     function run() public {
//         uint256 privateKey = vm.envUint("PRIVATE_KEY");
//         vm.startBroadcast(privateKey);

//         Setup.deploySystem();

//         vm.stopBroadcast();
//     }
// }

// /// @dev steps to deploy and verify on Optimism Goerli:
// /// (1) load the variables in the .env file via `source .env`
// /// (2) run `forge script script/Deploy.s.sol:DeployOptimismGoerli --rpc-url $OPTIMISM_GOERLI_RPC_URL --etherscan-api-key $OPTIMISM_ETHERSCAN_API_KEY --broadcast --verify -vvvv`

// contract DeployOptimismGoerli is Setup, OptimismGoerliParameters {
//     function run() public {
//         uint256 privateKey = vm.envUint("PRIVATE_KEY");
//         vm.startBroadcast(privateKey);

//         Setup.deploySystem();

//         vm.stopBroadcast();
//     }
// }
