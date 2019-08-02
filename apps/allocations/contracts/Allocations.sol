pragma solidity ^0.4.24;

import "@aragon/os/contracts/apps/AragonApp.sol";

import "@tps/apps-address-book/contracts/AddressBook.sol";

import "@aragon/os/contracts/lib/math/SafeMath.sol";

import "@aragon/os/contracts/lib/math/SafeMath64.sol";

import "@aragon/apps-vault/contracts/Vault.sol";


/*******************************************************************************
    Copyright 2018, That Planning Suite
    This program is free software: you can redistribute it and/or modify
    it under the terms of the GNU General Public License as published by
    the Free Software Foundation, either version 3 of the License, or
    (at your option) any later version.

    This program is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
    GNU General Public License for more details.
    You should have received a copy of the GNU General Public License
    along with this program.  If not, see <http://www.gnu.org/licenses/>.
*******************************************************************************/

/*******************************************************************************
* @title Allocations Contract
* @author Arthur Lunn
* @dev This contract is meant to handle tasks like basic budgeting,
*      and any time that tokens need to be distributed based on a certain
*      percentage breakdown to an array of addresses. Currently it works with ETH
*      needs to be adapted to work with tokens.
*******************************************************************************/
contract Allocations is AragonApp {

    using SafeMath for uint256;
    using SafeMath64 for uint64;
    using SafeERC20 for ERC20;

    bytes32 constant public CREATE_ACCOUNT_ROLE = keccak256("CREATE_ACCOUNT_ROLE");
    bytes32 constant public CREATE_ALLOCATION_ROLE = keccak256("CREATE_ALLOCATION_ROLE");
    bytes32 constant public EXECUTE_ALLOCATION_ROLE = keccak256("EXECUTE_ALLOCATION_ROLE");
    bytes32 constant public EXECUTE_PAYOUT_ROLE = keccak256("EXECUTE_PAYOUT_ROLE");
    bytes32 public constant CHANGE_PERIOD_ROLE = keccak256("CHANGE_PERIOD_ROLE");
    bytes32 public constant CHANGE_BUDGETS_ROLE = keccak256("CHANGE_BUDGETS_ROLE");

    uint256 internal constant MAX_UINT256 = uint256(-1);
    uint64 internal constant MAX_UINT64 = uint64(-1);
    uint64 internal constant MINIMUM_PERIOD = uint64(1 days);
    uint256 internal constant MAX_SCHEDULED_PAYOUTS_PER_TX = 20;

    string private constant ERROR_NO_PERIOD = "ALLOCATIONS_NO_PERIOD";
    string private constant ERROR_SET_PERIOD_TOO_SHORT = "ALLOCATIONS_SET_PERIOD_TOO_SHORT";
    string private constant ERROR_COMPLETE_TRANSITION = "ALLOCATIONS_COMPLETE_TRANSITION";

    struct Payout {
        bytes32[] candidateKeys;
        address[] candidateAddresses;
        uint256[] supports;
        string metadata;
        uint64 recurrences;
        uint64[] executions;
        uint64 period;
        uint256 amount;
        uint64 startTime;
        bool distSet;
        string description;
    }

    struct Account {
        Payout[] payouts;
        string metadata;
        //uint limit;
        uint256 balance;
        //address proxy;
        address token;
        bool hasBudget;
        uint256 budget;
        // future
        //mapping(address => uint256)balances;

    }

    struct AccountStatement {
        mapping(address => uint256) expenses;
        mapping(address => uint256) income;
    }

    struct Period {
        uint64 startTime;
        uint64 endTime;
        uint256 firstTransactionId;
        uint256 lastTransactionId;
        mapping (uint256 => AccountStatement) accountStatement;
    }

    AddressBook public addressBook;
    Vault public vault;
    Account[] accounts;
    mapping (uint64 => Period) periods;
    uint64 periodsLength;
    uint64 periodDuration;
    //Payout[] payouts;
    mapping(address => uint) accountProxies; // proxy address -> account Id

    event PayoutExecuted(uint256 accountId, uint payoutId, uint candidateId);
    event NewAccount(uint256 accountId);
    event NewPeriod(uint64 indexed periodId, uint64 periodStarts, uint64 periodEnds);
    event FundAccount(uint256 accountId);
    event SetDistribution(uint256 accountId, uint payoutId);
    event PaymentFailure(uint256 accountId, uint256 payoutId, uint256 candidateId);
    event SetBudget(uint256 indexed accountId, uint256 amount, bool hasBudget);
    event ChangePeriodDuration(uint64 newDuration);
    event Time(uint64 time);

    modifier periodExists(uint64 _periodId) {
        require(_periodId < periodsLength, ERROR_NO_PERIOD);
        _;
    }

    // Modifier used by all methods that impact accounting to make sure accounting period
    // is changed before the operation if needed
    // NOTE: its use **MUST** be accompanied by an initialization check
    modifier transitionsPeriod {
        //bool completeTransition = _tryTransitionAccountingPeriod(getMaxPeriodTransitions());
        require(
            _tryTransitionAccountingPeriod(getMaxPeriodTransitions()),
            ERROR_COMPLETE_TRANSITION
        );
        _;
    }

    /**
    * @dev This is the function that sets up who the candidates will be, and
    *      where the funds will go for the payout. This is where the payout
    *      object needs to be created in the payouts array.
    */
    function initialize(
        AddressBook _addressBook,
        Vault _vault,
        uint64 _periodDuration
    ) external onlyInit
    {
        addressBook = _addressBook;
        vault = _vault;
        require(_periodDuration >= MINIMUM_PERIOD, ERROR_SET_PERIOD_TOO_SHORT);
        periodDuration = _periodDuration;
        _newPeriod(getTimestamp64());
        accounts.length++;  // position 0 is reserved and unused
        initialized();
    }

///////////////////////
// Getter functions
///////////////////////
    function getAccount(uint256 _accountId) external view
    returns(string metadata, address token, bool hasBudget, uint256 budget)
    {
        Account storage account = accounts[_accountId];
        metadata = account.metadata;
        token = account.token;
        hasBudget = account.hasBudget;
        budget = account.budget;
    }

    function getPayout(uint _accountId, uint _payoutId) external view
    returns(uint amount, uint64 recurrences, uint startTime, uint period, bool distSet)
    {
        Payout storage payout = accounts[_accountId].payouts[_payoutId];
        amount = payout.amount;
        recurrences = payout.recurrences;
        startTime = payout.startTime;
        period = payout.period;
        distSet = payout.distSet;
    }

    function getPayoutDescription(uint _accountId, uint _payoutId) external view returns(string description) {
        Payout storage payout = accounts[_accountId].payouts[_payoutId];
        description = payout.description;
    }

    function getNumberOfCandidates(uint _accountId, uint _payoutId) external view
    returns(uint256 numCandidates)
    {
        Payout storage payout = accounts[_accountId].payouts[_payoutId];
        numCandidates = payout.supports.length;
    }

    function getPayoutDistributionValue(uint _accountId, uint256 _payoutId, uint256 idx) external view
    returns(uint256 supports)
    {
        Payout storage payout = accounts[_accountId].payouts[_payoutId];
        supports = payout.supports[idx];
    }

    /**
    * @dev We have to check for initialization as periods are only valid after initializing
    */
    function getCurrentPeriodId() external view isInitialized returns (uint64) {
        return _currentPeriodId();
    }

    function getPeriod(uint64 _periodId)
    external
    view
    periodExists(_periodId)
    returns (
        bool isCurrent,
        uint64 startTime,
        uint64 endTime,
        uint256 firstTransactionId,
        uint256 lastTransactionId
    )
    {
        Period storage period = periods[_periodId];

        isCurrent = _currentPeriodId() == _periodId;

        startTime = period.startTime;
        endTime = period.endTime;
        firstTransactionId = period.firstTransactionId;
        lastTransactionId = period.lastTransactionId;
    }

///////////////////////
// Payout functions
///////////////////////
    /**
    * @dev This is the function that sets up who the candidates will be, and
    *      where the funds will go for the payout. This is where the payout
    *      object needs to be created in the payouts array.
    * @notice Create allocation account '`_metadata`'
    * @param _metadata Any relevent label for the payout
    *
    */
    function newAccount(
        string _metadata,
        address _token,
        bool _hasBudget,
        uint256 _budget
    ) external auth(CREATE_ACCOUNT_ROLE) returns(uint256 accountId)
    {
        accountId = accounts.length++;
        Account storage account = accounts[accountId];
        account.metadata = _metadata;
        account.hasBudget = _hasBudget;
        account.budget = _budget;
        account.token = _token;
        emit NewAccount(accountId);
    }

    /**
    * @notice Change period duration to `@transformTime(_periodDuration)`, effective for next accounting period
    * @param _periodDuration Duration in seconds for accounting periods
    */
    function setPeriodDuration(uint64 _periodDuration)
        external
        auth(CHANGE_PERIOD_ROLE)
        transitionsPeriod
    {
        require(_periodDuration >= MINIMUM_PERIOD, ERROR_SET_PERIOD_TOO_SHORT);
        periodDuration = _periodDuration;
        emit ChangePeriodDuration(_periodDuration);
    }

    /**
    * @notice Set budget for account number `_accountId` to `@tokenAmount(0, _amount, false)`, effective immediately
    * @param _accountId Account Identifier
    * @param _amount New budget amount
    */
    function setBudget(
        uint256 _accountId,
        uint256 _amount
    )
        external
        auth(CHANGE_BUDGETS_ROLE)
        transitionsPeriod
    {
        accounts[_accountId].budget = _amount;
        if (!accounts[_accountId].hasBudget) {
            accounts[_accountId].hasBudget = true;
        }
        emit SetBudget(_accountId, _amount, true);
    }

    /**
    * @notice Remove spending limit for  account number `_accountId`, effective immediately
    * @param _accountId Address for token
    */
    function removeBudget(uint256 _accountId)
        external
        auth(CHANGE_BUDGETS_ROLE)
        transitionsPeriod
    {
        accounts[_accountId].budget = 0;
        accounts[_accountId].hasBudget = false;
        emit SetBudget(_accountId, 0, false);
    }

    /**
    * @dev This function distributes the payouts to the candidates in accordance with the distribution values
    * @notice Distribute allocation `_payoutId`
    * @param _payoutId Any relevent label for the payout
    * @param _accountId Account the payout belongs to
    */
    function runPayout(uint _accountId, uint256 _payoutId) public auth(EXECUTE_ALLOCATION_ROLE) returns(bool success) {
        success = _runPayout(_accountId, _payoutId);
    }

    /**
    * @dev This is the function that the DotVote will call. It doesn’t need
    *      to be called by a DotVote (options get weird if it's not)
    *      but for our use case the “CREATE_ALLOCATION_ROLE” will be given to
    *      the DotVote.
    * @notice Create a `@tokenAmount(_token, _amount)` allocation for ' `_description` '
    * @param _candidateAddresses Array of candidates to be allocated a portion of the payouut
    * @param _supports The Array of all support values for the various candidates. These values are set in dot voting
    * @param _accountId The Account used for the payout
    * @param _recurrences quantity used to indicate whether this is a recurring or one-time payout
    * @param _period time interval between each recurring payout
    * @param _amount The quantity of funds to be allocated
    * @param _description The distributions description
    */
    function setDistribution(
        address[] _candidateAddresses,
        uint256[] _supports,
        uint256[] /*unused_infoIndices*/,
        string /*unused_candidateInfo*/,
        string _description,
        uint256[] /*unused_level 1 ID - converted to bytes32*/,
        uint256[] /*unused_level 2 ID - converted to bytes32*/,
        uint256 _accountId,
        uint64 _recurrences,
        uint64 _startTime,
        uint64 _period,
        uint256 _amount
    ) public auth(CREATE_ALLOCATION_ROLE) transitionsPeriod returns(uint payoutId)
    {
        Account storage account = accounts[_accountId];
        require(vault.balance(account.token) >= _amount, "vault underfunded");
        require(_recurrences > 0, "must execute payout at least once");
        Payout storage payout = account.payouts[account.payouts.length++];

        payout.amount = _amount;
        payout.recurrences = _recurrences;
        payout.candidateAddresses = _candidateAddresses;

        if (_recurrences > 1) {
            payout.period = _period;
            // minimum granularity is a single day
            // This check can be disabled currently to enable testing of shorter times
            require(payout.period >= 1 days,"period too short");
        } else {
            payout.period = 0; // branch probably not needed
        }

        payout.startTime = _startTime; // solium-disable-line security/no-block-members
        payout.distSet = true;
        payout.supports = _supports;
        payout.description = _description;
        payout.executions.length = _supports.length;
        payoutId = account.payouts.length - 1;
        emit SetDistribution(_accountId, payoutId);
        if (_startTime <= getTimestamp64()) {
            _runPayout(_accountId, payoutId);
        }
    }

    function candidateExecutePayout(
        uint256 _accountId,
        uint256 _payoutId,
        uint256 _candidateId
    ) external transitionsPeriod
    {
        Payout storage payout = accounts[_accountId].payouts[_payoutId];
        require(payout.distSet);
        require(msg.sender == payout.candidateAddresses[_candidateId], "candidate not receiver");
        _executePayoutAtLeastOnce(_accountId, _payoutId, _candidateId);
    }

    function executePayout(
        uint256 _accountId,
        uint256 _payoutId,
        uint256 _candidateId
    ) external transitionsPeriod auth(EXECUTE_PAYOUT_ROLE)
    {
        Payout storage payout = accounts[_accountId].payouts[_payoutId];
        require(payout.distSet);
        //require(msg.sender == payout.candidateAddresses[_candidateId], "candidate not receiver");
        _executePayoutAtLeastOnce(_accountId, _payoutId, _candidateId);
    }

    function _executePayoutAtLeastOnce(uint256 _accountId, uint256 _payoutId, uint256 _candidateId) internal {
        Account storage account = accounts[_accountId];
        Payout storage payout = account.payouts[_payoutId];
        //require(!payout.inactive, ERROR_payout_INACTIVE);

        uint64 paid = 0;
        uint256 totalSupport = _getTotalSupport(payout);
        uint256 individualPayout = payout.supports[_candidateId].mul(payout.amount).div(totalSupport);
        emit Time(_nextPaymentTime(_accountId, _payoutId, _candidateId));
        while (_nextPaymentTime(_accountId, _payoutId, _candidateId) <= getTimestamp64() && paid < MAX_SCHEDULED_PAYOUTS_PER_TX) {
            if (!_canMakePayment(_accountId, individualPayout)) {
                emit PaymentFailure(_accountId, _payoutId, _candidateId);
                break;
            }

            // The while() predicate prevents these two from ever overflowing
            paid += 1;

            // We've already checked the remaining budget with `_canMakePayment()`
            _executeCandidatePayout(_accountId, _payoutId, _candidateId, totalSupport);
        }
    }

    function _newPeriod(uint64 _startTime) internal returns (Period storage) {
        // There should be no way for this to overflow since each period is at least one day
        uint64 newPeriodId = periodsLength++;

        Period storage period = periods[newPeriodId];
        period.startTime = _startTime;

        // Be careful here to not overflow; if startTime + periodDuration overflows, we set endTime
        // to MAX_UINT64 (let's assume that's the end of time for now).
        uint64 endTime = _startTime + periodDuration - 1;
        if (endTime < _startTime) { // overflowed
            endTime = MAX_UINT64;
        }
        period.endTime = endTime;

        emit NewPeriod(newPeriodId, period.startTime, period.endTime);

        return period;
    }

    function _tryTransitionAccountingPeriod(uint64 _maxTransitions) internal returns (bool success) {
        Period storage currentPeriod = periods[_currentPeriodId()];
        uint64 timestamp = getTimestamp64();

        // Transition periods if necessary
        while (timestamp > currentPeriod.endTime) {
            if (_maxTransitions == 0) {
                // Required number of transitions is over allowed number, return false indicating
                // it didn't fully transition
                return false;
            }
            // We're already protected from underflowing above
            _maxTransitions -= 1;

            // If there were any transactions in period, record which was the last
            // In case 0 transactions occured, first and last tx id will be 0
            //if (currentPeriod.firstTransactionId != NO_TRANSACTION) {
            //    currentPeriod.lastTransactionId = transactionsNextIndex.sub(1);
            //}

            // New period starts at end time + 1
            currentPeriod = _newPeriod(currentPeriod.endTime.add(1));
        }

        return true;
    }

    function _currentPeriodId() internal view returns (uint64) {
        // There is no way for this to overflow if protected by an initialization check
        return periodsLength - 1;
    }

    function _canMakePayment(uint256 _accountId, uint256 _amount) internal view returns (bool) {
        Account storage account = accounts[_accountId];
        return _getRemainingBudget(_accountId) >= _amount && vault.balance(account.token) >= _amount;
    }

    function _getRemainingBudget(uint256 _accountId) internal view returns (uint256) {
        Account storage account = accounts[_accountId];
        if (!account.hasBudget) {
            return MAX_UINT256;
        }

        uint256 budget = account.budget;
        uint256 spent = periods[_currentPeriodId()].accountStatement[_accountId].expenses[account.token];

        // A budget decrease can cause the spent amount to be greater than period budget
        // If so, return 0 to not allow more spending during period
        if (spent >= budget) {
            return 0;
        }

        // We're already protected from the overflow above
        return budget - spent;
    }

    function _runPayout(uint _accountId, uint256 _payoutId) internal returns(bool success) {
        Account storage account = accounts[_accountId];
        Payout storage payout = account.payouts[_payoutId];
        //uint256 totalSupport = _getTotalSupport(payout);
        uint i;
        //for (i = 0; i < payout.supports.length; i++) {
        //    totalSupport += payout.supports[i];
        //}
        // Payouts are now instantiated on setDistribution
        require(payout.distSet);


        uint individualPayout;
        address token = account.token;
        uint256 length = payout.candidateAddresses.length;
        //handle vault

        for (i = 0; i < length; i++) {
            //require(_nextPaymentTime(_accountId, _payoutId, i) < getTimestamp64(), "Too many recurrences");
            _executePayoutAtLeastOnce(_accountId, _payoutId, i);
        }
    
        success = true;
        //emit PayoutExecuted(_accountId, _payoutId);
    }

    function _getTotalSupport(Payout storage payout) internal returns (uint256 totalSupport) {
        for (uint256 i = 0; i < payout.supports.length; i++) {
            totalSupport += payout.supports[i];
        }
    }

    function _nextPaymentTime(uint256 _accountId, uint256 _payoutId, uint256 _candidateIndex) internal view returns (uint64) {
        Account storage account = accounts[_accountId];
        Payout storage payout = account.payouts[_payoutId];

        if (payout.executions[_candidateIndex] >= payout.recurrences) {
            return MAX_UINT64; // re-executes in some billions of years time... should not need to worry
        }

        // Split in multiple lines to circumvent linter warning
        uint64 increase = payout.executions[_candidateIndex].mul(payout.period);
        uint64 nextPayment = payout.startTime.add(increase);
        //emit Time(nextPayment);
        return nextPayment;
    }

    function _executeCandidatePayout(
        uint256 _accountId,
        uint256 _payoutId,
        uint256 _candidateIndex,
        uint256 _totalSupport
    ) internal
    {
        Account storage account = accounts[_accountId];
        Payout storage payout = account.payouts[_payoutId];

        //payout.executions[_candidateIndex] = payout.executions[_candidateIndex].add(1);
        uint256 individualPayout = payout.supports[_candidateIndex].mul(payout.amount).div(_totalSupport);

        //require(_canMakePayment(_accountId, individualPayout), "insufficient funds");

        address token = account.token;
        periods[_currentPeriodId()].accountStatement[_accountId].expenses[token] += individualPayout;
        payout.executions[_candidateIndex] += 1;
        vault.transfer(token, payout.candidateAddresses[_candidateIndex], individualPayout);
        emit PayoutExecuted(_accountId, _payoutId, _candidateIndex);
    }

    // Mocked fns (overrided during testing)
    // Must be view for mocking purposes

    function getMaxPeriodTransitions() internal view returns (uint64) { return MAX_UINT64; }
}
