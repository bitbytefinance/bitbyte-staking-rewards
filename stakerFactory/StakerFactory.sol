// SPDX-License-Identifier: MIT

pragma solidity 0.8.4;

import './interfaces/IStakerFactory.sol';
import './Staker.sol';

interface ISwapPair {
    function factory() external view returns(address);
}

contract StakerFactory is IStakerFactory {
    using Address for address;
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    mapping(address => mapping(address => address)) public stakers;
    mapping(address => StakerInfo) public stakerInfos;
    address[] public tokenStakers;
    address[] public lpStakers;

    address public immutable rlinkRelation;
    address public immutable swapFactory;

    struct StakerInfo {
        address creator;
        uint256 specialFeeRate;        
        bool isSpecialFee;
    }

    event StakerCreated(address indexed creator,address indexed stakingToken,address indexed rewardsToken,address staker);
    event CreatorChanged(address indexed oldCreator,address newCreator);

    constructor(
        address _rlinkRelation,
        address _swapFactory
    ){
        require(_rlinkRelation != address(0),"rlink relation can not be address 0");
        require(_swapFactory != address(0),"_swapFactory can not be address 0");

        rlinkRelation = _rlinkRelation;
        swapFactory = _swapFactory;
    }
    
    function stakersLength(bool isLpStaker) external view returns(uint){
        return isLpStaker ? lpStakers.length : tokenStakers.length;       
    }
    
    function getStaker(address stakingToken,address rewardsToken) external view returns(address,address) {
        address staker = stakers[stakingToken][rewardsToken];
        return (
            staker,
            stakerInfos[staker].creator
        );
    }

    function getStakerByIndex(uint index,bool isLpStaker) public view returns(address,address) {
        require(isLpStaker && index < lpStakers.length || !isLpStaker && index < tokenStakers.length,"invalid index");
        address staker = isLpStaker ? lpStakers[index] : tokenStakers[index];
        return (
            staker,
            stakerInfos[staker].creator
        );
    }
    
    function getStakerCreator(address staker) external view override returns(address){
        return stakerInfos[staker].creator;
    }

    // stakerParams[0]: address stakingToken
    // stakerParams[1]: address rewardsToken
    // stakerParams[2]: uint256 incentiveRate
    // stakerParams[3]: uint256 parentRate
    // stakerParams[4]: uint256 grandpaRate
    // stakerParams[5]: uint256 initReserve
    // stakerParams[6]: uint256 notifyAmount
    // stakerParams[7]: uint256 notifyBlocks
    // stakerParams[8]: bool isLpStaker
    function createStaker(bytes32[] memory stakerParams) external {
        address stakingToken = _bytes32ToAddress(stakerParams[0]); 
        address rewardsToken = _bytes32ToAddress(stakerParams[1]); 
        uint notifyAmount = uint(stakerParams[6]);
        uint initReserve = uint(stakerParams[5]);
        require(stakers[stakingToken][rewardsToken] == address(0),"staker already exists");
        require(notifyAmount <= initReserve,"invalid notify amount");
        require(uint(stakerParams[8]) == 0 || ISwapPair(stakingToken).factory() == swapFactory,"staking token is not lp token");

        bytes memory bytecode = type(Staker).creationCode;
        bytes32 salt = keccak256(abi.encodePacked(stakingToken, rewardsToken));
        address staker;
        assembly {
            staker := create2(0, add(bytecode, 32), mload(bytecode), salt)
        }
        IStaker staker_ = IStaker(staker);
        staker_.initialize(stakingToken, rewardsToken);
        staker_.setDistributeAgent(rlinkRelation);        
        if(uint(stakerParams[2]) > 0 || uint(stakerParams[3]) > 0 || uint(stakerParams[4]) > 0){
            staker_.setRefRates(uint(stakerParams[2]), uint(stakerParams[3]), uint(stakerParams[4]));  
        }

        stakers[stakingToken][rewardsToken] = staker;
        if(uint(stakerParams[8]) > 0){
            lpStakers.push(staker);
        }else{
            tokenStakers.push(staker);
        }

        stakerInfos[staker].creator = msg.sender;

        _addStakerReserve(staker,initReserve);
        staker_.notifyRewardAmount(notifyAmount,uint(stakerParams[7]));

        emit StakerCreated(msg.sender, stakingToken, rewardsToken, staker);
    }

    function notifyRewardWithAddReserve(address staker, uint reserve, uint reward,uint rewardsDuration) public {
        require(staker != address(0),"staker can not be address 0");
        require(msg.sender == stakerInfos[staker].creator,"forbidden");

        uint availableReserve = IStaker(staker).availableReserve();
        uint needReserve = availableReserve >= reward ? 0 : reward.sub(availableReserve);
        needReserve = Math.max(reserve,needReserve);
        if(needReserve > 0){
            _addStakerReserve(staker, needReserve);
        }
        IStaker(staker).notifyRewardAmount(reward, rewardsDuration);
    }

    function AddStakerReserve(address staker,uint reserve) external {
        require(staker != address(0),"staker can not be address 0");
        require(msg.sender == stakerInfos[staker].creator,"forbidden");
        _addStakerReserve(staker, reserve);
    }

    function _addStakerReserve(address staker,uint reserve) internal {
        IStaker staker_ = IStaker(staker);
        address rewardsToken = staker_.getRewardsToken();
        uint stakerOldBalance = IERC20(rewardsToken).balanceOf(staker);
        IERC20(rewardsToken).safeTransferFrom(msg.sender,staker,reserve);
        staker_.refreshReserve(stakerOldBalance);
    }

    function setRefRates(address staker,uint256 incentiveRate,uint256 parentRate,uint256 grandpaRate) external {
        require(staker != address(0),"staker can not be address 0");
        require(msg.sender == IStaker(staker).creator(),"caller must be creator");
        IStaker(staker).setRefRates(incentiveRate, parentRate, grandpaRate);
    }

    function takeExcessReserve(address staker, address to) external {
        require(staker != address(0),"staker can not be address 0");
        require(msg.sender == IStaker(staker).creator(),"caller must be creator");

        IStaker(staker).takeExcessReserve(to);
    }

    function _bytes32ToAddress(bytes32 buffer) internal pure returns(address){
        uint ui = uint(buffer);
        require(ui <= type(uint160).max,"bytes32 overflow uint160");

        return address(uint160(ui));
    }
}