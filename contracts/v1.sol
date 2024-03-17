// SPDX-License-Identifier: CC-BY-NC-ND
pragma solidity ^0.8.20;
pragma abicoder v2;

import "@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol";
import "@uniswap/v3-periphery/contracts/libraries/TransferHelper.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol"; // Import IERC20 from OpenZeppelin

interface IWETH {
    function deposit() external payable;

    function transfer(address to, uint256 value) external returns (bool);

    function withdraw(uint256) external;
}

interface IUniswapRouter is ISwapRouter {
    function refundETH() external payable;

    function sweepToken(
        address token,
        uint256 amountMinimum,
        address recipient
    ) external payable;
}

contract SubscriptionContract {
    ISwapRouter public immutable swapRouter;
    IWETH private weth;

    address private constant ROUTER_ADDRESS =
        0xE592427A0AEce92De3Edee1F18E0157C05861564;
    address public constant WMATIC = 0x0d500B1d8E8eF31E21C99d1Db9A6444d3ADf1270; // Polygon WMATIC
    address public OutputToken = 0x3c499c542cEF5E3811e1192ce70d8cC03d5c3359; // USDC Token on Polygon Testnet
    // address public OutputToken = 0x11fE4B6AE13d2a6055C8D9cF65c55bac32B5d844; // DAI Token on Goerli Testnet
    // address public immutable USDC = 0x07865c6E87B9F70255377e024ace6630C1Eaa37F; // USDC Token Address

    uint24 public constant poolFee = 3000; // Fee tier for Uniswap pool

    IUniswapRouter public constant uniswapRouter =
        IUniswapRouter(ROUTER_ADDRESS);

    address public owner;
    address public broker;
    uint256 public brokerShare; // Broker's percentage share (0-100)

    event SubscriptionSuccessful(
        uint256 contentId,
        address indexed subscriber,
        address indexed contentCreator,
        uint256 usdcAmount,
        uint256 indexed offeringId,
        address agency
    );

    modifier onlyOwner() {
        require(msg.sender == owner, "Only the owner can perform this action");
        _;
    }

    constructor() {
        owner = msg.sender;
        broker = msg.sender;
        brokerShare = 20;
        swapRouter = ISwapRouter(ROUTER_ADDRESS);
        weth = IWETH(WMATIC);
    }

    function subscribe(
        uint256 _contentId,
        address _contentCreator,
        address _agency,
        uint256 _agencyShare,
        uint256 _offeringId,
        address _inputToken,
        uint256 _outputAmount,
        uint256 _amountInMaximum
    ) external payable {
        require(
            _contentCreator != address(0),
            "Content creator's address cannot be zero"
        );
        require(_agencyShare <= 100, "Agency share cannot be over 100%");
        if (msg.value > 0) {
            // Swap ETH to USDC
            // swapExactInputSingleETH(WMATIC, OutputToken, msg.value);
            ExactOutputSingleETH(_outputAmount);
        } else if (OutputToken == _inputToken) {
            // Handle USDC
            require(_outputAmount > 0, "Zero Output Amount");
            IERC20(OutputToken).transferFrom(
                msg.sender,
                address(this),
                _outputAmount
            );
        } else {
            // totalUSDC = swapToken2Token(_inputToken, _inputTokenAmount);
            ExactOutputSingleToken(_outputAmount, _amountInMaximum);
        }
        // Calculate USDC payments
        uint256 brokerPayment = (_outputAmount * brokerShare) / 100;
        uint256 remainingPayment = _outputAmount - brokerPayment;
        uint256 agencyPayment = (remainingPayment * _agencyShare) / 100;
        uint256 creatorPayment = remainingPayment - agencyPayment;

        // Transfer USDC to broker, agency, and content creator
        IERC20(OutputToken).transfer(broker, brokerPayment);
        if (_agency != address(0) && _agencyShare > 0) {
            IERC20(OutputToken).transfer(_agency, agencyPayment);
        }
        IERC20(OutputToken).transfer(_contentCreator, creatorPayment);
        emit SubscriptionSuccessful(
            _contentId,
            msg.sender,
            _contentCreator,
            _outputAmount,
            _offeringId,
            _agency
        );
    }

    function ExactOutputSingleToken(
        uint256 outputTokenAmount,
        uint256 _amountInMaximum
    ) internal {
        require(outputTokenAmount > 0, "Must pass non 0 Output amount");

        IERC20(WMATIC).transferFrom(msg.sender, address(this), _amountInMaximum);
        IERC20(WMATIC).approve(address(swapRouter), type(uint256).max);

        ISwapRouter.ExactOutputSingleParams memory params = ISwapRouter
            .ExactOutputSingleParams(
                WMATIC,
                OutputToken,
                poolFee,
                address(this),
                block.timestamp + 300,
                outputTokenAmount,
                _amountInMaximum,
                0
            );

        swapRouter.exactOutputSingle(params);
        // refund leftover ETH to user
        IERC20(WMATIC).transfer(msg.sender, checkBalance(WMATIC));
    }

    function ExactOutputSingleETH(uint256 outputTokenAmount) internal {
        require(outputTokenAmount > 0, "Must pass non 0 Output amount");
        require(msg.value > 0, "Must pass non 0 ETH amount");
        uint256 amountInMaximum = msg.value;

        ISwapRouter.ExactOutputSingleParams memory params = ISwapRouter
            .ExactOutputSingleParams(
                WMATIC,
                OutputToken,
                poolFee,
                address(this),
                block.timestamp + 300,
                outputTokenAmount,
                amountInMaximum,
                0
            );

        swapRouter.exactOutputSingle{value: msg.value}(params);
        uniswapRouter.refundETH();

        // refund leftover ETH to user
        (bool success, ) = msg.sender.call{value: address(this).balance}("");
        require(success, "refund failed");
    }

    function updateBrokerShare(uint256 _newShare) external onlyOwner {
        require(_newShare <= 100, "Broker share cannot be over 100%");
        brokerShare = _newShare;
    }

    function updateBrokerAddress(address _newAddress) external onlyOwner {
        require(_newAddress != address(0), "Address cannot be zero");
        broker = _newAddress;
    }

    function updateOutputToken(address _newAddress) external onlyOwner {
        require(_newAddress != address(0), "Address cannot be zero");
        OutputToken = _newAddress;
    }

    function withdrawBalance() external onlyOwner {
        payable(owner).transfer(address(this).balance);
    }

    receive() external payable {}

    function checkBalance(address tokenAddress) public view returns (uint256) {
        return IERC20(tokenAddress).balanceOf(address(this));
    }

    function checkETHBalance() public view returns (uint256) {
        return address(this).balance;
    }
}
