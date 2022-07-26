// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

interface IFractonVesting {
  event VestingScheduleCreated(
    address indexed vestingLocation,
    uint32 cliffDuration,
    uint32 duration,
    uint32 interval,
    bool isRevocable
  );

  event VestingTokensGranted(
    address indexed beneficiary,
    uint256 vestingAmount,
    uint32 startDay,
    address vestingLocation
  );

  event VestingTokensClaimed(address indexed beneficiary, uint256 amount);

  event GrantRevoked(address indexed grantHolder);

  struct vestingSchedule {
    bool isRevocable; /* true if the vesting option is revocable (a gift), false if irrevocable (purchased) */
    uint32 cliffDuration; /* Duration of the cliff, with respect to the grant start day, in days. */
    uint32 duration; /* Duration of the vesting schedule, with respect to the grant start day, in days. */
    uint32 interval; /* Duration in days of the vesting interval. */
  }

  struct tokenGrant {
    bool isActive; /* true if this vesting entry is active and in-effect entry. */
    bool wasRevoked; /* true if this vesting schedule was revoked. */
    address vestingLocation; /* Address of wallet that is holding the vesting schedule. */
    uint32 startDay; /* Start day of the grant, in days since the UNIX epoch (start of day). */
    uint256 amount; /* Total number of tokens that vest. */
    uint256 claimedAmount; /* Out of vested amount, the amount that has been already transferred to beneficiary */
  }

  function withdrawTokens(address beneficiary, uint256 amount) external;

  // =========================================================================
  // === Methods for claiming tokens.
  // =========================================================================

  function claimVestingTokens(address beneficiary) external;

  function claimVestingTokensForAll() external;

  // =========================================================================
  // === Methods for administratively creating a vesting schedule for an account.
  // =========================================================================

  function setVestingSchedule(
    address vestingLocation,
    uint32 cliffDuration,
    uint32 duration,
    uint32 interval,
    bool isRevocable
  ) external;

  // =========================================================================
  // === Token grants (general-purpose)
  // === Methods to be used for administratively creating one-off token grants with vesting schedules.
  // =========================================================================

  function addGrant(
    address beneficiary,
    uint256 vestingAmount,
    uint32 startDay,
    uint32 duration,
    uint32 cliffDuration,
    uint32 interval,
    bool isRevocable
  ) external;

  function addGrantWithScheduleAt(
    address beneficiary,
    uint256 vestingAmount,
    uint32 startDay,
    address vestingLocation
  ) external;

  function addGrantFromToday(
    address beneficiary,
    uint256 vestingAmount,
    uint32 duration,
    uint32 cliffDuration,
    uint32 interval,
    bool isRevocable
  ) external;

  // =========================================================================
  // === Check vesting.
  // =========================================================================

  function today() external view returns (uint32 dayNumber);

  function getGrantInfo(address grantHolder, uint32 onDayOrToday)
    external
    view
    returns (
      uint256 amountVested,
      uint256 amountNotVested,
      uint256 amountOfGrant,
      uint256 amountAvailable,
      uint256 amountClaimed,
      uint32 vestStartDay,
      bool isActive,
      bool wasRevoked
    );

  function getScheduleAtInfo(address vestingLocation)
    external
    view
    returns (
      bool isRevocable,
      uint32 vestDuration,
      uint32 cliffDuration,
      uint32 vestIntervalDays
    );

  function getScheduleInfo(address grantHolder)
    external
    view
    returns (
      bool isRevocable,
      uint32 vestDuration,
      uint32 cliffDuration,
      uint32 vestIntervalDays
    );

  // =========================================================================
  // === Grant revocation
  // =========================================================================

  function revokeGrant(address grantHolder) external;
}
