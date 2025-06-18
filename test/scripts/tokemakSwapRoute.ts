import { getLiquidations } from "@tokemak/autopilot-swap-route-calc";
import axios from "axios";
import dotenv from "dotenv";
import { AutopilotRouter__factory } from "./contracts/factories/AutopilotRouter__factory.ts";

dotenv.config();

interface SwapRouteResult {
  success: boolean;
  results: {
    aggregator: string;
    fromToken: string;
    toToken: string;
    sellAmount: string;
    buyAmount: string;
    target: string;
    data: string;
  }[];
}

const args = process.argv.slice(2);
const SENDER = args[0];
const AUTO_ETH_SHARES_AMOUNT = BigInt(args[1]);
const MIN_AMOUNT_WETH = BigInt(args[2]);

async function main(SENDER: string, AUTO_ETH_SHARES_AMOUNT: bigint, MIN_AMOUNT_WETH: bigint) {

        const CHAIN_ID = 1n; // ethereum mainnet
        // https://docs.tokemak.xyz/developer-docs/contracts-overview/contract-addresses
        const SYSTEM_REGISTRY = "0x2218F90A98b0C070676f249EF44834686dAa4285";
        const PROVIDER_RPC_URL = process.env.RPC_URL || "";
        const AUTOPOOL = "0x0A2b94F6871c1D7A32Fe58E1ab5e6deA2f114E56";

        // Amount to pad the liquidation estimate by. This is to cover to any movements
        // on-chain between now and when you execute to ensure your swap estimates cover
        const TOKEN_PAD_BPS = 100n;

        const result = await getLiquidations(
            CHAIN_ID,
            SYSTEM_REGISTRY,
            PROVIDER_RPC_URL,
            AUTOPOOL,
            AUTO_ETH_SHARES_AMOUNT,
            TOKEN_PAD_BPS
        );

        // If using the Tokemak API to get the swap payloads
        const swaps = await axios.post('https://dynamic-swap-routes.tokemaklabs.xyz', JSON.stringify({
                chainId: CHAIN_ID,
                systemName: "gen3",
                slippageBps: 20,
                tokensToLiquidate: result.liquidations
            },  (_, v) => (typeof v === "bigint" ? v.toString() : v)), {
            headers: {
                'Content-Type': 'application/json'
            }
        })

        const swapData = swaps.data as SwapRouteResult;

        const router = AutopilotRouter__factory.createInterface();

        const multicall = [
            router.encodeFunctionData("redeemWithRoutes", [
              AUTOPOOL,
              SENDER, // Send WETH to SENDER
              AUTO_ETH_SHARES_AMOUNT,
              MIN_AMOUNT_WETH, // Min Amount WETH
              swapData.results.map((x) => {
                return {
                  fromToken: x.fromToken,
                  toToken: x.toToken,
                  target: x.target,
                  data: x.data,
                };
              }),
            ]),
          ];


        const fnToExecute = router.encodeFunctionData("multicall", [multicall]);

        process.stdout.write(fnToExecute);
}

main(SENDER, AUTO_ETH_SHARES_AMOUNT, MIN_AMOUNT_WETH);