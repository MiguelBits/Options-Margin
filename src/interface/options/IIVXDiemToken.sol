// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

interface IIVXDiemToken {
    event OptionCreated(uint256 optionID, uint256 strikePrice, address underlyingAsset, uint256 expiry);
    event OptionSettled(uint256 optionID, uint256 settlementPayoff);

    error IVXOptionIdNotFound(uint256 optionID);
    error IVXOptionIsStillTradeable(uint256 optionID);
    error IVXOptionExpired(uint256 optionID);
    error IVXOption_isSettled(uint256 optionID);
    error IVXOption_ExpiryBufferReached(uint256 optionID, uint256 expiryBuffer);
    error IVXOptionNotTradeable_DeltaCutoffReached(uint256 optionID, uint256 deltaCutoff);
    error IVXERC1155NotSupported();
    error AddressZero();
    error OnlyIVXDiem();
    error OnlyUseLastIdCreatedOfThisOptionGroups();
    error AlreadyInitialized();
    error BinomialCutoffMustBeSmallerThanBsCutoff();
    error OptionIdNotFound();
    error CannotCreateOptionWithExpiryAfterNextEpoch();
    error AssetShockLossFactorsNotSet();
    error OptionTradingParamsNotSet();
    error AssetMakerTakerParamsNotSet();
    
    struct MAKER_TAKER_FACTORS {
        uint256 VEGA_MAKER_FACTOR;
        uint256 VEGA_TAKER_FACTOR;
        uint256 DELTA_MAKER_FACTOR;
        uint256 DELTA_TAKER_FACTOR;
    }

    struct Option {
        uint256 expiry;
        uint256 strikePrice;
        address underlyingAsset;
    }

    struct OptionStatus {
        bool isSettled;
        uint256 settlementPayoff;
    }

    struct OptionAttributes {
        Option option;
        bool isCall;
        bool isBuy;
        OptionStatus status;
    }

    struct OptionTradingParams {
        uint256 deltaCutoff;
        uint256 expiryBuffer;
        uint256 binomialCutoff;
        uint256 blackScholesCutoff;
        uint256 FEE_TAKEN_PROFITS;
    }

    function currentOptionId() external view returns (uint256);

    function getUnderlyings() external view returns (address[] memory);

    function isTradeable(uint256 _optionID) external view;

    function calculateCosts(uint256 _optionID, uint256 _amountContracts, bool _isClose)
        external
        view
        returns (uint256 fee, uint256 premium, int256 delta, uint256 vega);
    function settleOptionsExpired(uint256 _optionID) external;

    function calculateSettlementFee(uint256 _value, uint256 _amountContracts) external view returns (uint256);

    function mint(address _to, uint256 _optionID, uint256 _amount) external;
    function burn(address _to, uint256 _optionID, uint256 _amount) external;
    function getUnderlying_ActiveOptions(address _underlying) external view returns (uint256[] memory);
    function getOptionIDAttributes(uint256 _optionID) external view returns (OptionAttributes memory);
    function getContractsExposure(uint256 id) external view returns (int256, int256);
    function totalSupply(uint256 _optionID) external view returns (uint256);
    function getCutoffs() external view returns (uint256, uint256);
}
