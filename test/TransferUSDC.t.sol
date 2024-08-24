// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {Test, console, Vm} from "forge-std/Test.sol";
import {MockCCIPRouter} from "@chainlink/contracts-ccip/src/v0.8/ccip/test/mocks/MockRouter.sol";
import {TransferUSDC} from "../src/TransferUSDC.sol";
import {CrossChainReceiver} from "../src/CrossChainReceiver.sol";
import {BurnMintERC677} from "@chainlink/contracts-ccip/src/v0.8/shared/token/ERC677/BurnMintERC677.sol";
import {LinkToken} from "@chainlink/contracts-ccip/src/v0.8/shared/token/ERC677/LinkToken.sol";

/**
 * @title TransferUSDCTest
 * @dev A test suite to estimate the gas usage during ccip cross-chain USDC transfer via crossChainTransferUsdc contract
 */
contract transferUSDCTest is Test {
    /// Declaration of the contracts, tokens and variables used in the tests
    TransferUSDC public transferUSDC;
    CrossChainReceiver public crossChainReceiver;

    LinkToken public link;
    BurnMintERC677 public usdcToken;
    MockCCIPRouter public router;

    address public cometAddress;
    address public swapTestnetUsdcAddress;

    uint64 constant ETHEREUM_SEPOLIA_CHAIN_SELECTOR = 16015286601757825753;
    uint64 constant DEFAULT_GAS_LIMIT = 500_000;
    uint256 constant AMOUNT_TO_TRANSFER = 1_000_000;

    /// @dev Sets up the testing environment by deploying necessary contracts and configuring their states.
    function setUp() public {
        /// Deploy Mock router and LINK token contracts to simulate the network environment.
        router = new MockCCIPRouter();
        link = new LinkToken();
        usdcToken = new BurnMintERC677("USDC Token", "USDC", 6, 10 ** 12);

        usdcToken.grantMintRole(address(this));

        // Deploy the contracts
        crossChainReceiver = new CrossChainReceiver(
            address(router),
            cometAddress,
            swapTestnetUsdcAddress
        );

        transferUSDC = new TransferUSDC(
            address(router),
            address(link),
            address(usdcToken)
        );

        /// Mint USDC tokens to `this contract` and approve them for the transferUSDC contract
        usdcToken.mint(address(this), 10000000);
        usdcToken.approve(address(transferUSDC), 10000000);

        /// Allow destination chain on the TransferUSDCWithIterations contract
        transferUSDC.allowlistDestinationChain(
            ETHEREUM_SEPOLIA_CHAIN_SELECTOR,
            true
        );

        /// Allow source chain and the sender (TransferUSDCWithIterations contract) on the CrossChainReceiver contract
        crossChainReceiver.allowlistSourceChain(
            ETHEREUM_SEPOLIA_CHAIN_SELECTOR,
            true
        );
        crossChainReceiver.allowlistSender(address(transferUSDC), true);
    }

    /**
     * @dev Sends a cross-chain message and records the gas usage from the logs.
     * @param iterations_ The variable to simulate varying loads in the message.
     * @param gasLimit_ The maximum amount of gas consumed to executed the ccipReceive function on the destination contract on the destination chain
     * @return The amount of gas used for the cross-chain transfer.
     */
    function sendMessage(
        uint256 iterations_,
        uint64 gasLimit_
    ) private returns (uint256) {
        vm.recordLogs(); // Start recording logs to capture gas usage

        // Execute the USDC transfer across chains
        transferUSDC.transferUsdc(
            ETHEREUM_SEPOLIA_CHAIN_SELECTOR,
            address(crossChainReceiver),
            AMOUNT_TO_TRANSFER,
            iterations_,
            gasLimit_
        );

        // Retrieve the recorded logs and gas used
        Vm.Log[] memory logs = vm.getRecordedLogs();
        bytes32 msgExecutedSignature = keccak256(
            "MsgExecuted(bool,bytes,uint256)"
        );

        uint256 gasUsed = 0;
        for (uint i = 0; i < logs.length; i++) {
            if (logs[i].topics[0] == msgExecutedSignature) {
                (, , gasUsed) = abi.decode(
                    logs[i].data,
                    (bool, bytes, uint256)
                );
            }
            console.log(
                "Number of iterations %d - Gas used: %d",
                iterations_,
                gasUsed
            );
        }

        return gasUsed;
    }

    /// @dev Calculate the optimized gas limit and apply it to a transfer
    function test_estimateAndApplyGasLimit() public {
        /// Measure the baseline, avarage and peak gas consumptions
        uint256 minGasUsed = sendMessage(0, DEFAULT_GAS_LIMIT);
        uint256 avgGasUsed = sendMessage(50, DEFAULT_GAS_LIMIT);
        uint256 maxGasUsed = sendMessage(99, DEFAULT_GAS_LIMIT);

        /// Calculate the optimal gas limit
        uint256 finalGasLimit = (minGasUsed + avgGasUsed + maxGasUsed) / 3;
        finalGasLimit = finalGasLimit + (finalGasLimit / 10);
        console.log(
            "Measured gas consumption to use (the average of the three previous values + 10% of it): ",
            finalGasLimit
        );

        /// Call transferUsdc with the optimised gas limit
        bytes32 messageId = transferUSDC.transferUsdc(
            ETHEREUM_SEPOLIA_CHAIN_SELECTOR,
            address(crossChainReceiver),
            AMOUNT_TO_TRANSFER,
            1,
            uint64(finalGasLimit)
        );
        console.log("messageId of the transferred message: ", messageId);
    }
}
