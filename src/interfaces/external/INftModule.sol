// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

/**
 * @title ERC721 non-fungible token (NFT) contract.
 */
interface IERC721 {
    /**
     * @notice Thrown when an address attempts to provide allowance to itself.
     * @param addr The address attempting to provide allowance.
     */
    error CannotSelfApprove(address addr);

    /**
     * @notice Thrown when attempting to transfer a token to an address that does not satisfy IERC721Receiver requirements.
     * @param addr The address that cannot receive the tokens.
     */
    error InvalidTransferRecipient(address addr);

    /**
     * @notice Thrown when attempting to specify an owner which is not valid (ex. the 0x00000... address)
     */
    error InvalidOwner(address addr);

    /**
     * @notice Thrown when attempting to operate on a token id that does not exist.
     * @param id The token id that does not exist.
     */
    error TokenDoesNotExist(uint256 id);

    /**
     * @notice Thrown when attempting to mint a token that already exists.
     * @param id The token id that already exists.
     */
    error TokenAlreadyMinted(uint256 id);

    /**
     * @notice Emitted when `tokenId` token is transferred from `from` to `to`.
     */
    event Transfer(address indexed from, address indexed to, uint256 indexed tokenId);

    /**
     * @notice Emitted when `owner` enables `approved` to manage the `tokenId` token.
     */
    event Approval(address indexed owner, address indexed approved, uint256 indexed tokenId);

    /**
     * @notice Emitted when `owner` enables or disables (`approved`) `operator` to manage all of its assets.
     */
    event ApprovalForAll(address indexed owner, address indexed operator, bool approved);

    /**
     * @notice Returns the number of tokens in ``owner``'s account.
     *
     * Requirements:
     *
     * - `holder` must be a valid address
     */
    function balanceOf(address holder) external view returns (uint256 balance);

    /**
     * @notice Returns the owner of the `tokenId` token.
     *
     * Requirements:
     *
     * - `tokenId` must exist.
     */
    function ownerOf(uint256 tokenId) external view returns (address owner);

    /**
     * @notice Safely transfers `tokenId` token from `from` to `to`.
     *
     * Requirements:
     *
     * - `from` cannot be the zero address.
     * - `to` cannot be the zero address.
     * - `tokenId` token must exist and be owned by `from`.
     * - If the caller is not `from`, it must be approved to move this token by either {approve} or {setApprovalForAll}.
     * - If `to` refers to a smart contract, it must implement {IERC721Receiver-onERC721Received}, which is called upon a safe transfer.
     *
     * Emits a {Transfer} event.
     */
    function safeTransferFrom(
        address from,
        address to,
        uint256 tokenId,
        bytes calldata data
    ) external;

    /**
     * @notice Safely transfers `tokenId` token from `from` to `to`, checking first that contract recipients
     * are aware of the ERC721 protocol to prevent tokens from being forever locked.
     *
     * Requirements:
     *
     * - `from` cannot be the zero address.
     * - `to` cannot be the zero address.
     * - `tokenId` token must exist and be owned by `from`.
     * - If the caller is not `from`, it must have been allowed to move this token by either {approve} or {setApprovalForAll}.
     * - If `to` refers to a smart contract, it must implement {IERC721Receiver-onERC721Received}, which is called upon a safe transfer.
     *
     * Emits a {Transfer} event.
     */
    function safeTransferFrom(address from, address to, uint256 tokenId) external;

    /**
     * @notice Transfers `tokenId` token from `from` to `to`.
     *
     * WARNING: Usage of this method is discouraged, use {safeTransferFrom} whenever possible.
     *
     * Requirements:
     *
     * - `from` cannot be the zero address.
     * - `to` cannot be the zero address.
     * - `tokenId` token must be owned by `from`.
     * - If the caller is not `from`, it must be approved to move this token by either {approve} or {setApprovalForAll}.
     *
     * Emits a {Transfer} event.
     */
    function transferFrom(address from, address to, uint256 tokenId) external;

    /**
     * @notice Gives permission to `to` to transfer `tokenId` token to another account.
     * The approval is cleared when the token is transferred.
     *
     * Only a single account can be approved at a time, so approving the zero address clears previous approvals.
     *
     * Requirements:
     *
     * - The caller must own the token or be an approved operator.
     * - `tokenId` must exist.
     *
     * Emits an {Approval} event.
     */
    function approve(address to, uint256 tokenId) external;

    /**
     * @notice Approve or remove `operator` as an operator for the caller.
     * Operators can call {transferFrom} or {safeTransferFrom} for any token owned by the caller.
     *
     * Requirements:
     *
     * - The `operator` cannot be the caller.
     *
     * Emits an {ApprovalForAll} event.
     */
    function setApprovalForAll(address operator, bool approved) external;

    /**
     * @notice Returns the account approved for `tokenId` token.
     *
     * Requirements:
     *
     * - `tokenId` must exist.
     */
    function getApproved(uint256 tokenId) external view returns (address operator);

    /**
     * @notice Returns if the `operator` is allowed to manage all of the assets of `owner`.
     *
     * See {setApprovalForAll}
     */
    function isApprovedForAll(address owner, address operator) external view returns (bool);
}

/**
 * @title ERC721 extension with helper functions that allow the enumeration of NFT tokens.
 */
interface IERC721Enumerable is IERC721 {
    /**
     * @notice Thrown calling *ByIndex function with an index greater than the number of tokens existing
     * @param requestedIndex The index requested by the caller
     * @param length The length of the list that is being iterated, making the max index queryable length - 1
     */
    error IndexOverrun(uint256 requestedIndex, uint256 length);

    /**
     * @dev Returns the total amount of tokens stored by the contract.
     */
    function totalSupply() external view returns (uint256);

    /**
     * @dev Returns a token ID owned by `owner` at a given `index` of its token list.
     * Use along with {balanceOf} to enumerate all of ``owner``'s tokens.
     *
     * Requirements:
     * - `owner` must be a valid address
     * - `index` must be less than the balance of the tokens for the owner
     */
    function tokenOfOwnerByIndex(address owner, uint256 index) external view returns (uint256);

    /**
     * @dev Returns a token ID at a given `index` of all the tokens stored by the contract.
     * Use along with {totalSupply} to enumerate all tokens.
     *
     * Requirements:
     * - `index` must be less than the total supply of the tokens
     */
    function tokenByIndex(uint256 index) external view returns (uint256);
}

/**
 * @title Module wrapping an ERC721 token implementation.
 */
interface INftModule is IERC721Enumerable {
    /**
     * @notice Returns whether the token has been initialized.
     * @return A boolean with the result of the query.
     */
    function isInitialized() external view returns (bool);

    /**
     * @notice Initializes the token with name, symbol, and uri.
     */
    function initialize(
        string memory tokenName,
        string memory tokenSymbol,
        string memory uri
    ) external;

    /**
     * @notice Allows the owner to mint tokens.
     * @param to The address to receive the newly minted tokens.
     * @param tokenId The ID of the newly minted token
     */
    function mint(address to, uint256 tokenId) external;

    /**
     * @notice Allows the owner to mint tokens. Verifies that the receiver can receive the token
     * @param to The address to receive the newly minted token.
     * @param tokenId The ID of the newly minted token
     * @param data any data which should be sent to the receiver
     */
    function safeMint(address to, uint256 tokenId, bytes memory data) external;

    /**
     * @notice Allows the owner to burn tokens.
     * @param tokenId The token to burn
     */
    function burn(uint256 tokenId) external;

    /**
     * @notice Allows an address that holds tokens to provide allowance to another.
     * @param tokenId The token which should be allowed to spender
     * @param spender The address that is given allowance.
     */
    function setAllowance(uint256 tokenId, address spender) external;

    /**
     * @notice Allows the owner to update the base token URI.
     * @param uri The new base token uri
     */
    function setBaseTokenURI(string memory uri) external;
}
