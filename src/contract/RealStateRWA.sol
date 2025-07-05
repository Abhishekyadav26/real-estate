// SPDX-License-Identifier: MIT

pragma solidity 0.8.25;

import {ERC721Enumerable, ERC721} from "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title RealEstateRWA
 * @notice A marketplace for tokenized real estate properties
 * @dev This contract represents real-world properties as NFTs
 */
// It allows for property listing, verification, purchase requests, and state management
contract RealEstateRWA is ERC721Enumerable, Ownable {
    uint256 private _tokenIds;

    // Enum to track property state
    enum PropertyState {
        INITIAL_OFFERING,
        FOR_SALE,
        PENDING_SALE,
        SOLD,
        NOT_FOR_SALE
    }

    // Structure to store property details
    struct Property {
        string propertyAddress;
        uint256 price; // in wei
        uint256 squareMeters;
        string legalIdentifier; // legal deed/title reference
        string documentHash; // IPFS hash of legal documents
        PropertyState state;
        address verifier; // address that verified this property
        string tokenURI; // URI pointing to the property metadata/image
    }

    // Maps tokenId to Property details
    mapping(uint256 => Property) public properties;

    // List of approved verifiers who can attest to property ownership
    mapping(address => bool) public approvedVerifiers;

    // Tracks pending purchases
    struct PendingPurchase {
        address buyer;
        uint256 amount;
        bool exists;
    }
    mapping(uint256 => PendingPurchase) public pendingPurchases;

    // Events
    event PropertyListed(
        uint256 indexed tokenId,
        string propertyAddress,
        uint256 price
    );
    event PropertyVerified(uint256 indexed tokenId, address verifier);
    event PropertySold(
        uint256 indexed tokenId,
        address from,
        address to,
        uint256 price
    );
    event PurchaseRequested(
        uint256 indexed tokenId,
        address buyer,
        uint256 amount
    );
    event PurchaseCompleted(uint256 indexed tokenId, address buyer);
    event PurchaseFailed(uint256 indexed tokenId, address buyer, string reason);
    event PropertyStateChanged(uint256 indexed tokenId, PropertyState newState);
    event TokenURIUpdated(uint256 indexed tokenId, string newTokenURI);

    constructor() ERC721("Real Estate RWA", "REALESTATE") Ownable(msg.sender) {
        // Add contract deployer as first approved verifier
        approvedVerifiers[msg.sender] = true;
    }

    /**
     * @dev Returns whether a token exists
     * @param tokenId The ID of the token to check
     * @return bool whether the token exists
     */
    function _exists(uint256 tokenId) internal view returns (bool) {
        return ownerOf(tokenId) != address(0);
    }

    /**
     * @notice Add a new approved verifier
     * @dev Only the contract owner can add verifiers
     * @param verifier The address to approve as a verifier
     */
    function addVerifier(address verifier) external onlyOwner {
        approvedVerifiers[verifier] = true;
    }

    /**
     * @notice Remove a verifier
     * @dev Only the contract owner can remove verifiers
     * @param verifier The address to remove as a verifier
     */
    function removeVerifier(address verifier) external onlyOwner {
        approvedVerifiers[verifier] = false;
    }

    /**
     * @notice Create a new property token
     * @dev Property is minted to the contract owner/caller
     * @param propertyAddress Physical address of the property
     * @param price Listed price in wei
     * @param squareMeters Size of the property
     * @param legalIdentifier Legal identifier of the property (e.g., deed number)
     * @param documentHash IPFS hash of legal documents
     * @param imageURI IPFS URI pointing to the property image
     * @return tokenId The ID of the newly created property token
     */
    function createProperty(
        string memory propertyAddress,
        uint256 price,
        uint256 squareMeters,
        string memory legalIdentifier,
        string memory documentHash,
        string memory imageURI
    ) external onlyOwner returns (uint256) {
        _tokenIds++;
        uint256 newTokenId = _tokenIds;

        _safeMint(owner(), newTokenId);

        properties[newTokenId] = Property({
            propertyAddress: propertyAddress,
            price: price,
            squareMeters: squareMeters,
            legalIdentifier: legalIdentifier,
            documentHash: documentHash,
            state: PropertyState.INITIAL_OFFERING,
            verifier: address(0), // Not verified yet
            tokenURI: imageURI
        });

        emit PropertyListed(newTokenId, propertyAddress, price);

        return newTokenId;
    }

    /**
     * @notice Set or update the tokenURI for a property
     * @dev Only the owner can update the token URI
     * @param tokenId The ID of the property
     * @param newTokenURI The new URI for the property metadata
     */
    function setTokenURI(uint256 tokenId, string memory newTokenURI) external {
        require(_exists(tokenId), "Property does not exist");
        require(ownerOf(tokenId) == msg.sender, "Not the owner");

        properties[tokenId].tokenURI = newTokenURI;
        emit TokenURIUpdated(tokenId, newTokenURI);
    }

    /**
     * @notice Returns the Uniform Resource Identifier (URI) for `tokenId` token.
     * @param tokenId The ID of the property
     * @return The URI for the given token
     */
    function tokenURI(
        uint256 tokenId
    ) public view virtual override returns (string memory) {
        require(_exists(tokenId), "URI query for nonexistent token");
        return properties[tokenId].tokenURI;
    }

    /**
     * @notice Verify a property token
     * @dev Only approved verifiers can verify properties
     * @param tokenId The ID of the property to verify
     */
    function verifyProperty(uint256 tokenId) external {
        require(approvedVerifiers[msg.sender], "Not an approved verifier");
        require(_exists(tokenId), "Property does not exist");
        require(properties[tokenId].verifier == address(0), "Already verified");

        properties[tokenId].verifier = msg.sender;

        emit PropertyVerified(tokenId, msg.sender);
    }

    /**
     * @notice Update property state and optionally price
     * @param tokenId The ID of the property
     * @param newState The new state for the property
     * @param newPrice Optional new price (0 to keep current price)
     */
    function updatePropertyState(
        uint256 tokenId,
        PropertyState newState,
        uint256 newPrice
    ) external {
        require(ownerOf(tokenId) == msg.sender, "Not the owner");

        properties[tokenId].state = newState;

        if (newPrice > 0) {
            properties[tokenId].price = newPrice;
        }

        emit PropertyStateChanged(tokenId, newState);

        if (newState == PropertyState.FOR_SALE) {
            emit PropertyListed(
                tokenId,
                properties[tokenId].propertyAddress,
                properties[tokenId].price
            );
        }
    }

    /**
     * @notice Request to purchase a property
     * @dev Buyer sends ETH as part of transaction
     * @param tokenId The ID of the property to purchase
     */
    function requestPurchase(uint256 tokenId) external payable {
        require(_exists(tokenId), "Property does not exist");
        require(
            properties[tokenId].state == PropertyState.FOR_SALE,
            "Property not for sale"
        );
        require(
            properties[tokenId].verifier != address(0),
            "Property not verified"
        );
        require(msg.value >= properties[tokenId].price, "Insufficient payment");
        require(!pendingPurchases[tokenId].exists, "Purchase already pending");

        // Create pending purchase
        pendingPurchases[tokenId] = PendingPurchase({
            buyer: msg.sender,
            amount: msg.value,
            exists: true
        });

        // Update property state
        properties[tokenId].state = PropertyState.PENDING_SALE;
        emit PropertyStateChanged(tokenId, PropertyState.PENDING_SALE);

        emit PurchaseRequested(tokenId, msg.sender, msg.value);

        // Note: In a real implementation, this would trigger off-chain processing
        // to handle the legal transfer of the property
    }

    /**
     * @notice Complete a pending purchase (after off-chain processing)
     * @dev Only the contract owner can complete purchases
     * @param tokenId The ID of the property
     * @param success Whether the purchase was successful
     * @param reason Optional reason if the purchase failed
     */
    function completePurchase(
        uint256 tokenId,
        bool success,
        string memory reason
    ) external onlyOwner {
        require(pendingPurchases[tokenId].exists, "No pending purchase");

        address buyer = pendingPurchases[tokenId].buyer;
        uint256 amount = pendingPurchases[tokenId].amount;
        address seller = ownerOf(tokenId);

        // Clear the pending purchase
        delete pendingPurchases[tokenId];

        if (success) {
            // Transfer the property token
            _transfer(seller, buyer, tokenId);

            // Transfer the payment to the seller
            (bool sent, ) = payable(seller).call{value: amount}("");
            require(sent, "Failed to send payment to seller");

            // Update property status
            properties[tokenId].state = PropertyState.SOLD;
            emit PropertyStateChanged(tokenId, PropertyState.SOLD);

            emit PurchaseCompleted(tokenId, buyer);
            emit PropertySold(tokenId, seller, buyer, amount);
        } else {
            // Refund the buyer
            (bool sent, ) = payable(buyer).call{value: amount}("");
            require(sent, "Failed to refund buyer");

            // Reset property status
            properties[tokenId].state = PropertyState.FOR_SALE;
            emit PropertyStateChanged(tokenId, PropertyState.FOR_SALE);

            emit PurchaseFailed(tokenId, buyer, reason);
        }
    }

    /**
     * @notice Get property details
     * @param tokenId The ID of the property
     * @return Property details
     */
    function getProperty(
        uint256 tokenId
    ) external view returns (Property memory) {
        require(_exists(tokenId), "Property does not exist");
        return properties[tokenId];
    }

    function getTotalProperties() external view returns (uint256) {
        return _tokenIds;
    }

    function getAllProperties() external view returns (Property[] memory) {
        Property[] memory allProperties = new Property[](_tokenIds);
        for (uint256 i = 1; i <= _tokenIds; i++) {
            allProperties[i - 1] = properties[i];
        }
        return allProperties;
    }

    /**
     * @notice Get all properties owned by an address
     * @param owner The address to check
     * @return Array of property IDs owned by the address
     */
    function getPropertiesOfOwner(
        address owner
    ) external view returns (uint256[] memory) {
        uint256 balance = balanceOf(owner);
        uint256[] memory result = new uint256[](balance);

        for (uint256 i = 0; i < balance; i++) {
            result[i] = tokenOfOwnerByIndex(owner, i);
        }

        return result;
    }
}