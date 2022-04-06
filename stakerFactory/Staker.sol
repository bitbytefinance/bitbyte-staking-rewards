// SPDX-License-Identifier: MIT

pragma solidity 0.8.4;

import "../libs/Math.sol";
import "../libs/SafeMath.sol";
import "../libs/SafeERC20.sol";
import "../libs/ReentrancyGuard.sol";
import "../libs/IRlinkCore.sol";
import "./interfaces/IStakerFactory.sol";
import "./interfaces/IStaker.sol";

contract Staker is ReentrancyGuard,IStaker {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;
    /* ========== STATE VARIABLES ========== */

    IERC20 public stakingToken;
    IERC20 public rewardsToken;
    uint256 public override periodFinish;
    uint256 public override rewardRate;

    uint256 public rewardsDuration; 
    uint256 public lastUpdateBlock;
    uint256 public rewardPerTokenStored;

    mapping(address => uint256) public userRewardPerTokenPaid;
    mapping(address => uint256) public rewards;

    uint256 private _totalSupply;
    mapping(address => uint256) private _balances;

    address public override creator;
    address public immutable override factory;
    uint256 public immutable override createTime;
    address public rlink;

    uint256 public incentiveRate;
    uint256 public parentRate;
    uint256 public grandpaRate;

    uint256 public totalReserve;
    uint256 public expendedReserve;
    uint256 public unusedReserve;
    uint256 public noStakeBlock;
    uint256 public periodStart;

    /* ========== MODIFIERS ========== */

    modifier onlyCreator {
        require(msg.sender == creator,"forbidden");
        _;
    }

    modifier updateReward(address account) {
        rewardPerTokenStored = rewardPerToken(block.number);
        lastUpdateBlock = lastBlockRewardApplicable(block.number);
        if (account != address(0)) {
            rewards[account] = earned(account);
            userRewardPerTokenPaid[account] = rewardPerTokenStored;
        }
        _;
    }

    constructor() {
        require(Address.isContract(msg.sender),"staker can only create by staker factory");
        factory = msg.sender;
        createTime = block.timestamp;
    }

    function initialize(
        address _creator,
        address _stakingToken,
        address _rewardsToken,
        address _rlink,
        uint _incentiveRate,
        uint _parentRate,
        uint _grandpaRate
    ) external override {
        require(msg.sender == factory, 'forbidden');
        require(_incentiveRate.add(_parentRate).add(_grandpaRate) <= 1e18,"sum of rates can not greater than 1e18");
        require(_creator != address(0),"creator can not be address 0");
        
        creator = _creator;
        stakingToken = IERC20(_stakingToken);
        rewardsToken = IERC20(_rewardsToken);
        rlink = _rlink;        
    }

    function getStakingToken() external view override returns(address){
        return address(stakingToken);
    }

    function getRewardsToken() external view override returns(address){
        return address(rewardsToken);
    }

    function totalSupply() external view override returns (uint256) {
        return _totalSupply;
    }

    function balanceOf(address account) external view override returns (uint256) {
        return _balances[account];
    }

    function lastBlockRewardApplicable(uint256 toBlock) public view returns (uint256) {
        return toBlock < periodFinish ? toBlock : periodFinish;
    }

    function rewardPerToken(uint256 toBlock) public view returns (uint256) {
        require(toBlock >= lastUpdateBlock,"toBlock must greater than lastUpdateBlock");
        if (_totalSupply == 0) {
            return rewardPerTokenStored;
        }
        return
            rewardPerTokenStored.add(
                lastBlockRewardApplicable(toBlock).sub(lastUpdateBlock).mul(rewardRate).mul(1e18).div(_totalSupply)
            );
    }

    function pendingReward(address account, uint256 toBlock) public view returns(uint256) {        
        return  _balances[account].mul(rewardPerToken(toBlock).sub(userRewardPerTokenPaid[account])).div(1e18);
    }

    function storedReward(address account) external view returns(uint256){
        return rewards[account];
    }

    function earned(address account) public view override returns (uint256) {
        return pendingReward(account,block.number).add(rewards[account]);
    }

    function getRewardForDuration() external view returns (uint256) {
        return rewardRate.mul(rewardsDuration);
    }

    function stake(uint256 amount) public nonReentrant updateReward(msg.sender) {
        require(amount > 0, "cannot stake 0");
        uint256 oldBalance = stakingToken.balanceOf(address(this));
        stakingToken.safeTransferFrom(msg.sender, address(this), amount);
        uint256 newBalance = stakingToken.balanceOf(address(this));
        require(newBalance > oldBalance,"receive 0 token");
        uint256 realAmount = newBalance.sub(oldBalance);

        _totalSupply = _totalSupply.add(realAmount);
        _balances[msg.sender] = _balances[msg.sender].add(realAmount);

        if(noStakeBlock > 0){
            unusedReserve = unusedReserve.add(pendingUnusedReserve());
            noStakeBlock = 0;
        }

        emit Staked(msg.sender, realAmount);
    }

    function withdraw(uint256 amount) public nonReentrant updateReward(msg.sender) {
        require(amount > 0, "cannot withdraw 0");
        _totalSupply = _totalSupply.sub(amount);
        _balances[msg.sender] = _balances[msg.sender].sub(amount);
        stakingToken.safeTransfer(msg.sender, amount);

        if(_totalSupply == 0){
            noStakeBlock = block.number;
        }

        emit Withdrawn(msg.sender, amount);
    }

    function withdrawReward() public nonReentrant updateReward(msg.sender) {
        uint256 reward = rewards[msg.sender];
        uint sendedReward = 0;
        if (reward > 0) {
            rewards[msg.sender] = 0;
            if(rlink == address(0)){
                rewardsToken.safeTransfer(msg.sender, reward);
                sendedReward = reward;
            }else{
                rewardsToken.safeApprove(rlink,reward);
                sendedReward = IRlinkCore(rlink).distribute(
                    address(rewardsToken),
                    msg.sender, 
                    reward,
                    reward.mul(incentiveRate).div(1e18),
                    reward.mul(parentRate).div(1e18),
                    reward.mul(grandpaRate).div(1e18)
                );
                require(sendedReward > 0,"distribute rewards failed");
            }

            emit RewardPaid(msg.sender, reward);
        }
    }

    function exit() external {
        withdraw(_balances[msg.sender]);
        withdrawReward();
    }

    function availableReserve() public view override returns(uint256){
        return totalReserve.add(unusedReserve).add(pendingUnusedReserve()).sub(expendedReserve).sub(pendingExpend());
    }

    function pendingUnusedReserve() public view returns(uint256){
        if(noStakeBlock == 0){
            return 0;
        }

        return rewardRate.mul(block.number.sub(noStakeBlock));
    }
    
    function pendingExpend() public view returns(uint256){
        if(periodStart == 0){
            return 0;
        }
        return Math.min(block.number,periodFinish).sub(periodStart).mul(rewardRate);
    }

    /* ========== RESTRICTED FUNCTIONS ========== */
    function notifyRewardAmount(uint256 _reward,uint256 _rewardsDuration) external override nonReentrant onlyCreator updateReward(address(0)) {
        require(_reward > 0,"reward can not be 0");
        require(_rewardsDuration > 0,"rewards duration can not be 0");
        require(_reward.div(_rewardsDuration) > 0,"provided reward too low");

        _updateUnusedReserve();

        uint availableReserve_ = availableReserve();
        if(availableReserve_ < _reward){
            uint oldBalance = rewardsToken.balanceOf(address(this));
            rewardsToken.safeTransferFrom(msg.sender, address(this), _reward - availableReserve_);
            uint received = rewardsToken.balanceOf(address(this)).sub(oldBalance);
            availableReserve_ = availableReserve_.add(received);
            totalReserve = totalReserve.add(received);
        }
        require(_reward <= availableReserve_,"insufficient received token");

        expendedReserve = expendedReserve.add(pendingExpend());
        rewardRate = _reward.div(_rewardsDuration);

        require(rewardRate <= availableReserve_.div(_rewardsDuration), "provided reward too high");
        if(_totalSupply == 0){
            noStakeBlock = block.number;
        }

        lastUpdateBlock = block.number;
        periodFinish = block.number.add(_rewardsDuration);
        rewardsDuration = _rewardsDuration;
        periodStart = block.number;
        emit RewardAdded(msg.sender, _reward);
    }

    function _updateUnusedReserve() internal {
        uint notStakeBlock_ = noStakeBlock;
        if(noStakeBlock > 0){
            unusedReserve = unusedReserve.add(pendingUnusedReserve());
            notStakeBlock_ = 0;
        }
        if(_totalSupply == 0){
            notStakeBlock_ = block.number;
        }
        noStakeBlock = notStakeBlock_;
    }
}
