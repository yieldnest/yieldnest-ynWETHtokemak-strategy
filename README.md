# Yieldnest Flex Strategy

## Deployment

Before running the script, ensure appropriate variables are set in
`script\DeployFlexStrategy.s.sol:assignDeploymentParameters()`

```
# deploy strategy
forge script DeployFlexStrategy --rpc-url <MAINNET_RPC_URL>  --slow --broadcast --account <CAST_WALLET_ACCOUNT>  --sender <SENDER_ADDRESS>  --verify --etherscan-api-key <ETHERSCAN_API_KEY>  -vvv

# verify deployment
forge script VerifyFlexStrategy --rpc-url <MAINNET_RPC_URL>
```
