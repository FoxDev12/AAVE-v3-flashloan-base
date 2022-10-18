//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;
import "./interfaces/IFlashloanSimpleReceiver.sol";
import "./interfaces/IERC20.sol";

contract FlashLoanBase is IFlashLoanSimpleReceiver {
    error NotEnoughFundsToRepayFlashloan(uint balance, uint wanted);
    error UnauthorizedInitiator(address initiator, address wanted);
    error SenderIsNotPool(address sender, address wanted);
    error NotOwner(address sender, address owner);
    error NotAdmin(address sender);
    IPoolAddressesProvider public immutable override ADDRESSES_PROVIDER;
    IPool public immutable override POOL;
    IERC20 public toBorrow;

    address public owner;
    mapping(address => bool) public admins;
    
    modifier onlyOwner() {
        address sender = msg.sender;
        if(sender != owner) {
            revert NotOwner(sender, owner);
        }
        _;
    }
    modifier onlyAdmin() {
        address sender = msg.sender;
        if(admins[sender] == false) {
            revert NotAdmin(sender);
        }
        _;
    }
    constructor(IPoolAddressesProvider provider, IERC20 _toBorrow) {
        ADDRESSES_PROVIDER = provider;
        POOL = IPool(provider.getPool());
        owner = msg.sender;
        admins[msg.sender] = true;
        toBorrow = _toBorrow;

    }


// --------------------------------------------------------------------------------- RESTRICTED FUNCTIONS -----------------------------------------------------------------------------

    function updateAsset(IERC20 newAsset) external onlyAdmin {
        toBorrow = newAsset;
    }
    function updateOwner(address newOwner) external onlyOwner {
        owner = newOwner;
        admins[msg.sender] = false;
        admins[newOwner] = true;
    }
    function flipAdmin(address admin) external onlyOwner {
        admins[admin] = !admins[admin];
    }
// --------------------------------------------------------------------------------- REQUEST ------------------------------------------------------------------------------------------
    // Override to add checks or logic if wanted. Encoded params might be passed to flashLoanLogic here.
    function requestFlashLoan(uint256 amount, bytes calldata params) public onlyAdmin virtual {
        POOL.flashLoanSimple(address(this), address(toBorrow), amount, params, 0);
    }

// --------------------------------------------------------------------------------- EXECUTE ------------------------------------------------------------------------------------------

    // Logic is contained inside of flashLoanLogic. This function performs checks before executing the logic and repaying the flashloan and should not be overridden. 
    function executeOperation(
        address asset,
        uint256 amount,
        uint256 premium,
        address initiator,
        bytes calldata params
    ) external returns (bool ok) {
        ok = false;
        
        if(msg.sender != address(POOL)) {
            revert SenderIsNotPool(msg.sender, address(POOL));
        }
        if(initiator != address(this)) {
            revert UnauthorizedInitiator(initiator, address(this));

        }
        flashLoanLogic(asset, amount, params);
        uint256 balanceAfter = IERC20(asset).balanceOf(address(this));
        if(balanceAfter < amount + premium) {
            // Doesn't let execution reach the pool to save gas. 
            revert NotEnoughFundsToRepayFlashloan(balanceAfter, amount + premium);
        }
        IERC20(asset).approve(address(POOL), amount + premium);
        ok = true;
    }

    // Override it in your own contract, or fill it in here directly
    function flashLoanLogic(address asset, uint256 amount, bytes calldata params) internal virtual {
        // The flashloan logic goes here. 
    }


// --------------------------------------------------------------------------------- WITHDRAW -----------------------------------------------------------------------------------------
    function withdrawERC20(address asset) external onlyOwner {
        IERC20(asset).transfer(msg.sender, IERC20(asset).balanceOf(address(this)));
    }
    function withdrawETH() external onlyOwner {
        (bool success, ) = payable(msg.sender).call{value: address(this).balance}("");
        require(success);
    }
  
  }