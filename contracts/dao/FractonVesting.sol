// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import '@openzeppelin/contracts/access/Ownable.sol';
import '@openzeppelin/contracts/utils/math/SafeMath.sol';
import '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import '../interface/IFractonVesting.sol';

contract FractonVesting is IFractonVesting, Context, Ownable {
  using SafeMath for uint256;

  // Date-related constants for sanity-checking dates to reject obvious erroneous inputs
  // and conversions from seconds to days and years that are more or less leap year-aware.
  uint32 private constant _THOUSAND_YEARS_DAYS = 365243; /* See https://www.timeanddate.com/date/durationresult.html?m1=1&d1=1&y1=2000&m2=1&d2=1&y2=3000 */
  uint32 private constant _TEN_YEARS_DAYS = _THOUSAND_YEARS_DAYS / 100; /* Includes leap years (though it doesn't really matter) */
  uint32 private constant _SECONDS_PER_DAY = 24 * 60 * 60; /* 86400 seconds in a day */
  uint32 private constant _JAN_1_2000_SECONDS = 946684800; /* Saturday, January 1, 2000 0:00:00 (GMT) (see https://www.epochconverter.com/) */
  uint32 private constant _JAN_1_2000_DAYS =
    _JAN_1_2000_SECONDS / _SECONDS_PER_DAY;
  uint32 private constant _JAN_1_3000_DAYS =
    _JAN_1_2000_DAYS + _THOUSAND_YEARS_DAYS;

  mapping(address => vestingSchedule) private _vestingSchedules;
  mapping(address => tokenGrant) private _tokenGrants;
  address[] private _allBeneficiaries;
  address public immutable vestingToken;

  constructor(address vestingToken_) {
    vestingToken = vestingToken_;
  }

  function withdrawTokens(address beneficiary, uint256 amount)
    external
    override
    onlyOwner
  {
    require(amount > 0, 'amount must be > 0');
    require(IERC20(vestingToken).transfer(beneficiary, amount));
  }

  // =========================================================================
  // === Methods for claiming tokens.
  // =========================================================================

  function claimVestingTokens(address beneficiary)
    public
    override
    onlyOwnerOrSelf(beneficiary)
  {
    uint256 amount = _getAvailableAmount(beneficiary, 0);
    if (amount > 0) {
      _tokenGrants[beneficiary].claimedAmount = _tokenGrants[beneficiary]
        .claimedAmount
        .add(amount);
      _deliverTokens(beneficiary, amount);
      emit VestingTokensClaimed(beneficiary, amount);
    }
  }

  function claimVestingTokensForAll() external override onlyOwner {
    for (uint256 i = 0; i < _allBeneficiaries.length; i++) {
      claimVestingTokens(_allBeneficiaries[i]);
    }
  }

  function _deliverTokens(address beneficiary, uint256 amount) internal {
    require(amount > 0, 'amount must be > 0');
    require(
      amount <= IERC20(vestingToken).balanceOf(address(this)),
      'amount exceeded balance'
    );
    require(
      _tokenGrants[beneficiary].claimedAmount.add(amount) <=
        _tokenGrants[beneficiary].amount,
      'claimed amount must be <= grant amount'
    );

    require(IERC20(vestingToken).transfer(beneficiary, amount));
  }

  // =========================================================================
  // === Methods for administratively creating a vesting schedule for an account.
  // =========================================================================

  /**
   * @dev This one-time operation permanently establishes a vesting schedule in the given account.
   *
   * @param cliffDuration = Duration of the cliff, with respect to the grant start day, in days.
   * @param duration = Duration of the vesting schedule, with respect to the grant start day, in days.
   * @param interval = Number of days between vesting increases.
   * @param isRevocable = True if the grant can be revoked (i.e. was a gift) or false if it cannot
   *   be revoked (i.e. tokens were purchased).
   */
  function setVestingSchedule(
    address vestingLocation,
    uint32 cliffDuration,
    uint32 duration,
    uint32 interval,
    bool isRevocable
  ) public override onlyOwner {
    // Check for a valid vesting schedule given (disallow absurd values to reject likely bad input).
    require(
      duration > 0 &&
        duration <= _TEN_YEARS_DAYS &&
        cliffDuration < duration &&
        interval >= 1,
      'invalid vesting schedule'
    );

    // Make sure the duration values are in harmony with interval (both should be an exact multiple of interval).
    require(
      duration % interval == 0 && cliffDuration % interval == 0,
      'invalid cliff/duration for interval'
    );

    // Create and populate a vesting schedule.
    _vestingSchedules[vestingLocation] = vestingSchedule(
      isRevocable,
      cliffDuration,
      duration,
      interval
    );

    // Emit the event.
    emit VestingScheduleCreated(
      vestingLocation,
      cliffDuration,
      duration,
      interval,
      isRevocable
    );
  }

  // =========================================================================
  // === Token grants (general-purpose)
  // === Methods to be used for administratively creating one-off token grants with vesting schedules.
  // =========================================================================

  /**
   * @dev Grants tokens to an account.
   *
   * @param beneficiary = Address to which tokens will be granted.
   * @param vestingAmount = The number of tokens subject to vesting.
   * @param startDay = Start day of the grant's vesting schedule, in days since the UNIX epoch
   *   (start of day). The startDay may be given as a date in the future or in the past, going as far
   *   back as year 2000.
   * @param vestingLocation = Account where the vesting schedule is held (must already exist).
   */
  function _addGrant(
    address beneficiary,
    uint256 vestingAmount,
    uint32 startDay,
    address vestingLocation
  ) internal {
    // Make sure no prior grant is in effect.
    require(!_tokenGrants[beneficiary].isActive, 'grant already exists');

    // Check for valid vestingAmount
    require(
      vestingAmount > 0 &&
        startDay >= _JAN_1_2000_DAYS &&
        startDay < _JAN_1_3000_DAYS,
      'invalid vesting params'
    );

    // Create and populate a token grant, referencing vesting schedule.
    _tokenGrants[beneficiary] = tokenGrant(
      true, // isActive
      false, // wasRevoked
      vestingLocation, // The wallet address where the vesting schedule is kept.
      startDay,
      vestingAmount,
      0 // claimedAmount
    );
    _allBeneficiaries.push(beneficiary);

    // Emit the event.
    emit VestingTokensGranted(
      beneficiary,
      vestingAmount,
      startDay,
      vestingLocation
    );
  }

  /**
   * @dev Grants tokens to an address, including a portion that will vest over time
   * according to a set vesting schedule. The overall duration and cliff duration of the grant must
   * be an even multiple of the vesting interval.
   *
   * @param beneficiary = Address to which tokens will be granted.
   * @param vestingAmount = The number of tokens subject to vesting.
   * @param startDay = Start day of the grant's vesting schedule, in days since the UNIX epoch
   *   (start of day). The startDay may be given as a date in the future or in the past, going as far
   *   back as year 2000.
   * @param duration = Duration of the vesting schedule, with respect to the grant start day, in days.
   * @param cliffDuration = Duration of the cliff, with respect to the grant start day, in days.
   * @param interval = Number of days between vesting increases.
   * @param isRevocable = True if the grant can be revoked (i.e. was a gift) or false if it cannot
   *   be revoked (i.e. tokens were purchased).
   */
  function addGrant(
    address beneficiary,
    uint256 vestingAmount,
    uint32 startDay,
    uint32 duration,
    uint32 cliffDuration,
    uint32 interval,
    bool isRevocable
  ) public override onlyOwner {
    // Make sure no prior vesting schedule has been set.
    require(!_tokenGrants[beneficiary].isActive, 'grant already exists');

    // The vesting schedule is unique to this wallet and so will be stored here,
    setVestingSchedule(
      beneficiary,
      cliffDuration,
      duration,
      interval,
      isRevocable
    );

    // Issue tokens to the beneficiary, using beneficiary's own vesting schedule.
    _addGrant(beneficiary, vestingAmount, startDay, beneficiary);
  }

  function addGrantWithScheduleAt(
    address beneficiary,
    uint256 vestingAmount,
    uint32 startDay,
    address vestingLocation
  ) external override onlyOwner {
    // Issue tokens to the beneficiary, using custom vestingLocation.
    _addGrant(beneficiary, vestingAmount, startDay, vestingLocation);
  }

  function addGrantFromToday(
    address beneficiary,
    uint256 vestingAmount,
    uint32 duration,
    uint32 cliffDuration,
    uint32 interval,
    bool isRevocable
  ) external override onlyOwner {
    addGrant(
      beneficiary,
      vestingAmount,
      today(),
      duration,
      cliffDuration,
      interval,
      isRevocable
    );
  }

  // =========================================================================
  // === Check vesting.
  // =========================================================================
  function today() public view virtual override returns (uint32 dayNumber) {
    return uint32(block.timestamp / _SECONDS_PER_DAY);
  }

  function _effectiveDay(uint32 onDayOrToday)
    internal
    view
    returns (uint32 dayNumber)
  {
    return onDayOrToday == 0 ? today() : onDayOrToday;
  }

  /**
   * @dev Determines the amount of tokens that have not vested in the given account.
   *
   * The math is: not vested amount = vesting amount * (end date - on date)/(end date - start date)
   *
   * @param grantHolder = The account to check.
   * @param onDayOrToday = The day to check for, in days since the UNIX epoch. Can pass
   *   the special value 0 to indicate today.
   */
  function _getNotVestedAmount(address grantHolder, uint32 onDayOrToday)
    internal
    view
    returns (uint256 amountNotVested)
  {
    tokenGrant storage grant = _tokenGrants[grantHolder];
    vestingSchedule storage vesting = _vestingSchedules[grant.vestingLocation];
    uint32 onDay = _effectiveDay(onDayOrToday);

    // If there's no schedule, or before the vesting cliff, then the full amount is not vested.
    if (!grant.isActive || onDay < grant.startDay + vesting.cliffDuration) {
      // None are vested (all are not vested)
      return grant.amount - grant.claimedAmount;
    }
    // If after end of vesting, then the not vested amount is zero (all are vested).
    else if (onDay >= grant.startDay + vesting.duration) {
      // All are vested (none are not vested)
      return uint256(0);
    }
    // Otherwise a fractional amount is vested.
    else {
      // Compute the exact number of days vested.
      uint32 daysVested = onDay - grant.startDay;
      // Adjust result rounding down to take into consideration the interval.
      uint32 effectiveDaysVested = (daysVested / vesting.interval) *
        vesting.interval;

      // Compute the fraction vested from schedule using 224.32 fixed point math for date range ratio.
      // Note: This is safe in 256-bit math because max value of X billion tokens = X*10^27 wei, and
      // typical token amounts can fit into 90 bits. Scaling using a 32 bits value results in only 125
      // bits before reducing back to 90 bits by dividing. There is plenty of room left, even for token
      // amounts many orders of magnitude greater than mere billions.
      uint256 vested = grant.amount.mul(effectiveDaysVested).div(
        vesting.duration
      );
      uint256 result = grant.amount.sub(vested);

      return result;
    }
  }

  /**
   * @dev Computes the amount of funds in the given account which are available for use as of
   * the given day, i.e. the claimable amount.
   *
   * The math is: available amount = totalGrantAmount - notVestedAmount - claimedAmount.
   *
   * @param grantHolder = The account to check.
   * @param onDay = The day to check for, in days since the UNIX epoch.
   */
  function _getAvailableAmount(address grantHolder, uint32 onDay)
    internal
    view
    returns (uint256 amountAvailable)
  {
    tokenGrant storage grant = _tokenGrants[grantHolder];
    return
      _getAvailableAmountImpl(grant, _getNotVestedAmount(grantHolder, onDay));
  }

  function _getAvailableAmountImpl(
    tokenGrant storage grant,
    uint256 notVastedOnDay
  ) internal view returns (uint256 amountAvailable) {
    uint256 vested = grant.amount.sub(notVastedOnDay);
    if (grant.wasRevoked) {
      return 0;
    }

    uint256 result = vested.sub(grant.claimedAmount);
    require(
      result <= grant.amount &&
        grant.claimedAmount.add(result) <= grant.amount &&
        result <= vested &&
        vested <= grant.amount
    );

    return result;
  }

  /**
   * @dev returns all information about the grant's vesting as of the given day
   * for the given account. Only callable by the account holder or a contract owner.
   *
   * @param grantHolder = The address to do this for.
   * @param onDayOrToday = The day to check for, in days since the UNIX epoch. Can pass
   *   the special value 0 to indicate today.
   * return = A tuple with the following values:
   *   amountVested = the amount that is already vested
   *   amountNotVested = the amount that is not yet vested (equal to vestingAmount - vestedAmount)
   *   amountOfGrant = the total amount of tokens subject to vesting.
   *   amountAvailable = the amount of funds in the given account which are available for use as of the given day
   *   amountClaimed = out of amountVested, the amount that has been already transferred to beneficiary
   *   vestStartDay = starting day of the grant (in days since the UNIX epoch).
   *   isActive = true if the vesting schedule is currently active.
   *   wasRevoked = true if the vesting schedule was revoked.
   */
  function getGrantInfo(address grantHolder, uint32 onDayOrToday)
    external
    view
    override
    returns (
      uint256 amountVested,
      uint256 amountNotVested,
      uint256 amountOfGrant,
      uint256 amountAvailable,
      uint256 amountClaimed,
      uint32 vestStartDay,
      bool isActive,
      bool wasRevoked
    )
  {
    tokenGrant storage grant = _tokenGrants[grantHolder];
    uint256 notVestedAmount = _getNotVestedAmount(grantHolder, onDayOrToday);

    return (
      grant.amount.sub(notVestedAmount),
      notVestedAmount,
      grant.amount,
      _getAvailableAmountImpl(grant, notVestedAmount),
      grant.claimedAmount,
      grant.startDay,
      grant.isActive,
      grant.wasRevoked
    );
  }

  function getScheduleAtInfo(address vestingLocation)
    public
    view
    override
    returns (
      bool isRevocable,
      uint32 vestDuration,
      uint32 cliffDuration,
      uint32 vestIntervalDays
    )
  {
    vestingSchedule storage vesting = _vestingSchedules[vestingLocation];

    return (
      vesting.isRevocable,
      vesting.duration,
      vesting.cliffDuration,
      vesting.interval
    );
  }

  function getScheduleInfo(address grantHolder)
    external
    view
    override
    returns (
      bool isRevocable,
      uint32 vestDuration,
      uint32 cliffDuration,
      uint32 vestIntervalDays
    )
  {
    tokenGrant storage grant = _tokenGrants[grantHolder];
    return getScheduleAtInfo(grant.vestingLocation);
  }

  // =========================================================================
  // === Grant revocation
  // =========================================================================

  /**
   * @dev If the account has a revocable grant, this forces the grant to end immediately.
   * After this function is called, getGrantInfo will return incomplete data
   * and there will be no possibility to claim non-claimed tokens
   *
   * @param grantHolder = Address to which tokens will be granted.
   */
  function revokeGrant(address grantHolder) external override onlyOwner {
    tokenGrant storage grant = _tokenGrants[grantHolder];
    vestingSchedule storage vesting = _vestingSchedules[grant.vestingLocation];

    // Make sure a vesting schedule has previously been set.
    require(grant.isActive, 'not active grant');
    // Make sure it's revocable.
    require(vesting.isRevocable, 'inrevocable');

    // Kill the grant by updating wasRevoked and isActive.
    _tokenGrants[grantHolder].wasRevoked = true;
    _tokenGrants[grantHolder].isActive = false;

    // Emits the GrantRevoked event.
    emit GrantRevoked(grantHolder);
  }

  modifier onlyOwnerOrSelf(address account) {
    require(
      _msgSender() == owner() || _msgSender() == account,
      'onlyOwnerOrSelf'
    );
    _;
  }
}
