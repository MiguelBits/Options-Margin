# Options-Margin

Margin protocol code ideas submitted for IVX.finance ,
Uses an uncommon option pricing method, Binomial Pricing model to price options within 1 days expiry to price better 0DTE options, as well as BlackScholes for longer options, and a mix of both for expirations in between.
Margin Requirements must be met to adquire leverage from AMM, and AMM hedges on any persp-DEX , gmx was choosen for this test.

Documentation: https://ivx-smart-contracts.gitbook.io/diem-documents

Diem is an options Automated Market Maker (AMM) which facilitates long and short options trading in a permissionless and decentralized way for options with less than 24 hours to expiry. In addition, it acts as a single pool, and offers options on multiple underlying assets which are collateralized by this pool. It is the first step toward unifying option liquidity into a single collateral pool for multiple assets and strike prices. It forms the foundation for expanding the IVX AMM to encompass a broad spectrum of expiry times.

Very early Audit by Guardian Audits: https://github.com/GuardianAudits/Audits/tree/main/IVX

Frontend by [@c0rdeiro](https://github.com/c0rdeiro)
   
Diagram
![image](https://github.com/MiguelBits/Options-Margin/assets/15989933/9c654fda-1cbb-4679-816f-dce2b5ae7cb3)
