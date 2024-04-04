// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import {ERC20} from "@solmate/tokens/ERC20.sol";

interface IIVXLP {
    struct StructuredForExposure {
        uint256 call_premium;
        uint256 put_premium;
        uint256 callsExposure;
        uint256 putsExposure;
        uint256 spot;
    }

    struct InterestRateParams {
        uint256 MaxRate;
        uint256 InflectionRate;
        uint256 MinRate;
        uint256 InflectionUtilization;
        uint256 MaxUtilization;
    }

    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/

    event Deposit(address indexed account, uint256 amount);
    event Withdraw(address indexed account, uint256 amount);

    /*//////////////////////////////////////////////////////////////
                                 ERRORS
    //////////////////////////////////////////////////////////////*/

    error OnlyAllowedContract(address _sender, address _allowedContract);
    error OnlyAllowedContracts(address _sender, address _allowedContract1, address _allowedContract2);
    error IVXLPInsufficientQueuedAssets(uint256 available, uint256 requested);
    error IVXLPInsuficcientCollateralCapacity(uint256 available, uint256 requested);
    error IVX_MaxUtilizationReached(uint256 utilizationRatio, uint256 maxUtilizationRatio);
    error AddressZero();
    error IVXLPZeroNAV();

    function laggingNAV() external returns (uint256);

    function updateLaggingNAV() external;

    function interestRate() external view returns (uint256);

    function deltaExposure(address asset) external view returns (int256);

    function transferQuoteToHedge(uint256 _amount) external returns (uint256);

    function transferCollateral(address _receiver, uint256 _amount) external;

    function queueContract() external view returns (address);

    function withdrawLiquidity(uint256 _shares, address _user) external;

    function collateral() external view returns (ERC20);

    function NAV() external view returns (uint256);

    function utilizedCollateral() external view returns (uint256);

    function utilizationRatio() external view returns (uint256);

    function maxUtilizationRatio() external view returns (uint256);

    function vaultMaximumCapacity() external view returns (uint256);

    function mint(address _user, uint256 _amount) external;

    function burn(address _user, uint256 _amount) external;

    function addUtilizedCollateral(uint256 _amount) external;

    function subUtilizedCollateral(uint256 _amount) external;

    function DeltaAndVegaExposure(address _asset) external view returns (int256, int256);
}
