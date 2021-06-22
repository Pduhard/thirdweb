// SPDX-License-Identifier: GPL-3.0 

pragma solidity >=0.8.0;

import "@openzeppelin/contracts/token/ERC1155/presets/ERC1155PresetMinterPauser.sol";

import "./PackControl.sol";
import "./interfaces/RNGInterface.sol";

/**
 * Implement burn function - emit TokenBurned
 *
 * Implement mint function - mint to pack handler.
 *
 * User has to set approve pack handler for all `setApprovalForAll(packHandler, true)`
 */

contract PackERC1155 is ERC1155PresetMinterPauser {

  PackControl internal controlCenter;
  address public packHandler;

  uint public currentTokenId;

  event TokenTransfer(address indexed from, address indexed to, uint[] tokenIds, uint[] amounts, uint tokenType);
  event TokenBurned(address indexed burner, uint indexed tokenId, uint amount);

  /// @dev tokenId => total supply of token.
  mapping(uint => uint) public circulatingSupply;

  /// @dev tokenId => URI.
  mapping(uint => string) public tokenUri;

  /// @dev tokenId => token type.
  mapping(uint => uint) public tokenType;

  constructor(address _controlCenter) ERC1155PresetMinterPauser("") {
    controlCenter = PackControl(_controlCenter);
    grantRole(PAUSER_ROLE, _controlCenter);
    grantRole(MINTER_ROLE, _controlCenter);
  }

  modifier onlyControlCenter() {
    require(msg.sender == address(controlCenter), "Only the protocol control center can call this function.");
    _;
  }

  modifier onlyPackHandler() {
    require(msg.sender == packHandler, "Only the protocol pack token handler can call this function.");
    _;
  }

  /// @dev Sets the pack handler for the protocol ERC1155 tokens.
  function setPackHandler(address _newHandler) external onlyControlCenter {
    if(packHandler != address(0)) {
      revokeRole(MINTER_ROLE, packHandler);
    }

    packHandler = _newHandler;
    grantRole(MINTER_ROLE, _newHandler);
  }

  /// @dev Called by the pack handler to mint new tokens.
  function mintTokens(
    address _to,
    uint _id,
    uint _amount,
    string calldata _uri,
    uint _tokenType
  ) external onlyPackHandler {

    // Update token state in mapping.
    circulatingSupply[_id] = _amount;
    tokenUri[_id] = _uri;
    tokenType[_id] = _tokenType;

    // Mint tokens to pack creator.
    mint(_to, _id, _amount, "");
  }

  /// @dev Overriding `burn`
  function burn(address account, uint256 id, uint256 value) public override onlyPackHandler {
    super.burn(account, id, value);
  }

  /// @dev Returns and then increments `currentTokenId`
  function _tokenId() public onlyPackHandler returns (uint tokenId) {
    tokenId = currentTokenId;
    currentTokenId++;
  }

  function _rng() public view onlyPackHandler returns (RNGInterface) {
    return RNGInterface(controlCenter.packRNG());
  }

  /**
   * @notice See the ERC1155 API. Returns the token URI of the token with id `tokenId`
   *
   * @param id The ERC1155 tokenId of a pack or reward token. 
   */
  function uri(uint id) public view override returns (string memory) {
    return tokenUri[id];
  }

  /**
   * @dev See OpenZeppelin ERC1155PresetMinterPauser signature of `_beforeTokenTransfer`
   */
  function _beforeTokenTransfer(
    address operator,
    address from,
    address to,
    uint256[] memory ids,
    uint256[] memory amounts,
    bytes memory data
  ) internal override {

    if(ids.length == 1) { 
      emit TokenTransfer(from, to, ids, amounts, tokenType[ids[0]]);
    } else {

      uint typeOfToken;

      for (uint i = 0; i < ids.length; i++) {
        uint tokenId = ids[i];

        if(i == 0) {
          typeOfToken = tokenType[tokenId];
          continue;
        } else if(tokenType[tokenId] != typeOfToken) {
          revert("Can only transfer a batch of the same type of token.");
        }
      }

      emit TokenTransfer(from, to, ids, amounts, typeOfToken);
    }
  }
}