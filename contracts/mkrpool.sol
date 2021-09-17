//SPDX-License-Identifier: Unlicense
pragma solidity ^0.6.2;

import "hardhat/console.sol";
import "@openzeppelin/contracts/math/Math.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/utils/Context.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";

contract LPTokenWrapper {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;
    IERC20 public stakeToken;

    constructor(address _stakeToken) public {
        stakeToken = IERC20(_stakeToken);
    }

    uint256 private _totalSupply;
    mapping(address => uint256) private _balances;

    function totalSupply() public view returns (uint256) {
        return _totalSupply;
    }

    function balanceOf(address account) public view returns (uint256) {
        return _balances[account];
    }

    function stake(uint256 amount) public virtual {
        _totalSupply = _totalSupply.add(amount);
        _balances[msg.sender] = _balances[msg.sender].add(amount);
        stakeToken.safeTransferFrom(msg.sender, address(this), amount);
    }

    function withdraw(uint256 amount) public virtual {
        _totalSupply = _totalSupply.sub(amount);
        _balances[msg.sender] = _balances[msg.sender].sub(amount);
        stakeToken.safeTransfer(msg.sender, amount);
    }
}

interface IDelegate {
    function delegate(address delegatee) external;
}

interface IVoteDelegate {
    function lock(uint256 wad) external;

    function free(uint256 wad) external;

    function vote(address[] memory yays) external returns (bytes32 result);

    function vote(bytes32 slate) external;

    // Polling vote
    function votePoll(uint256 pollId, uint256 optionId) external;

    function votePoll(uint256[] calldata pollIds, uint256[] calldata optionIds)
        external;

    function gov() external returns (address);

    function iou() external returns (address);
}

interface IVoteDelegateFactory {
    function create() external returns (address voteDelegate);
}

contract MKRVoteRewards is LPTokenWrapper {
    IVoteDelegate public voteDelegate;

    constructor(address _stakeToken) public LPTokenWrapper(_stakeToken) {
        voteDelegate = IVoteDelegate(
            IVoteDelegateFactory(0xD897F108670903D1d6070fcf818f9db3615AF272)
                .create()
        );
        IERC20 _gov = IERC20(voteDelegate.gov());
        IERC20 _iou = IERC20(voteDelegate.iou());
        _gov.approve(address(voteDelegate), type(uint256).max);
        _iou.approve(address(voteDelegate), type(uint256).max);
    }

    IERC20 public dai = IERC20(0xa1d0E215a23d7030842FC67cE582a6aFa3CCaB83);
    uint256 public constant DURATION = 7 days;

    address public sponsor;
    uint256 public sponsorshipAmount;
    string public link;

    uint256 public starttime = 0;
    uint256 public periodFinish = 0;
    uint256 public rewardRate = 0;
    uint256 public lastUpdateTime;
    uint256 public rewardPerTokenStored;
    mapping(address => uint256) public userRewardPerTokenPaid;
    mapping(address => uint256) public rewards;

    event RewardAdded(address sponsor, uint256 reward);
    event Staked(address indexed user, uint256 amount);
    event Withdrawn(address indexed user, uint256 amount);
    event RewardPaid(address indexed user, uint256 reward);

    modifier updateReward(address account) {
        rewardPerTokenStored = rewardPerToken();
        lastUpdateTime = lastTimeRewardApplicable();
        if (account != address(0)) {
            rewards[account] = earned(account);
            userRewardPerTokenPaid[account] = rewardPerTokenStored;
        }
        _;
    }

    function lastTimeRewardApplicable() public view returns (uint256) {
        return Math.min(block.timestamp, periodFinish);
    }

    function rewardPerToken() public view returns (uint256) {
        if (totalSupply() == 0) {
            return rewardPerTokenStored;
        }
        return
            rewardPerTokenStored.add(
                lastTimeRewardApplicable()
                    .sub(lastUpdateTime)
                    .mul(rewardRate)
                    .mul(1e18)
                    .div(totalSupply())
            );
    }

    function earned(address account) public view returns (uint256) {
        return
            balanceOf(account)
                .mul(rewardPerToken().sub(userRewardPerTokenPaid[account]))
                .div(1e18)
                .add(rewards[account]);
    }

    function stake(uint256 amount) public override updateReward(msg.sender) {
        require(amount > 0, "Cannot stake 0");
        super.stake(amount);
        voteDelegate.lock(amount);
        emit Staked(msg.sender, amount);
    }

    function withdraw(uint256 amount) public override updateReward(msg.sender) {
        require(amount > 0, "Cannot withdraw 0");
        voteDelegate.free(amount);
        super.withdraw(amount);
        emit Withdrawn(msg.sender, amount);
    }

    function exit() external {
        withdraw(balanceOf(msg.sender));
        getReward();
    }

    function getReward() public updateReward(msg.sender) {
        uint256 reward = earned(msg.sender);
        if (reward > 0) {
            rewards[msg.sender] = 0;
            dai.safeTransfer(msg.sender, reward);
            emit RewardPaid(msg.sender, reward);
        }
    }

    function addfun(uint256 reward, string memory _link)
        external
        updateReward(address(0))
    {
        if (block.timestamp >= periodFinish) {
            //new func
            dai.safeTransferFrom(msg.sender, address(this), reward);
            rewardRate = reward.div(DURATION);
            sponsor = msg.sender;
            sponsorshipAmount = reward;
        } else {
            //auction
            require(reward > sponsorshipAmount.mul(110).div(100), "");
            dai.safeTransferFrom(msg.sender, address(this), reward);

            uint256 remaining = periodFinish.sub(block.timestamp);
            uint256 leftover = remaining.mul(rewardRate);
            dai.safeTransfer(sponsor, leftover);

            rewardRate = reward.div(DURATION);
            sponsor = msg.sender;
            sponsorshipAmount = reward;
        }
        lastUpdateTime = block.timestamp;
        periodFinish = block.timestamp.add(DURATION);
        link = _link;
        emit RewardAdded(msg.sender, reward);
    }

    modifier isSponsor() {
        require(msg.sender == sponsor, "not sponsor!");
        _;
    }

    function vote(address[] memory yays)
        external
        isSponsor
        returns (bytes32 result)
    {
        return voteDelegate.vote(yays);
    }

    function vote(bytes32 slate) external isSponsor {
        voteDelegate.vote(slate);
    }

    // Polling vote
    function votePoll(uint256 pollId, uint256 optionId) external isSponsor {
        voteDelegate.votePoll(pollId, optionId);
    }

    function votePoll(uint256[] calldata pollIds, uint256[] calldata optionIds)
        external
        isSponsor
    {
        voteDelegate.votePoll(pollIds, optionIds);
    }
}
