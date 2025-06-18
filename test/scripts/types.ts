export interface SwapRouteResult {
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
