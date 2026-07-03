# Test Plan – OracleAIBounty

- Happy path: 2 participants → reveal → 3 oracles stake and vote → finalize winner
- Cannot reveal before deadline (reverts)
- Only oracles can vote (reverts for non-oracles)
- Cannot finalize without oracle votes (reverts)
- Oracle stake required (reverts if too low)
