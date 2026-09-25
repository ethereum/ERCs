/**
 * ERC-7965: Ethereum Intent URI (EIURI) Reference Implementation
 * 
 * This is a reference implementation of the Ethereum Intent URI parser
 * as specified in ERC-7965. It provides utilities to parse and validate
 * Ethereum Intent URIs and convert them to JSON-RPC requests.
 */

class EthereumIntentURI {
  /**
   * Creates a new EthereumIntentURI instance
   * @param {string} uri - The Ethereum Intent URI to parse
   */
  constructor(uri) {
    this.uri = uri;
    this.parsed = this.parse();
  }

  /**
   * Parses the Ethereum Intent URI into its components
   * @returns {Object} Parsed URI components
   */
  parse() {
    const regex = /^ethereum:([^-@?]+)(?:-([^@?]+))?(?:@(\d+))?(?:\?(.+))?$/;
    const match = this.uri.match(regex);
    
    if (!match) {
      throw new Error('Invalid Ethereum Intent URI format');
    }

    const [, rpcMethod, targetAddress, chainId, queryString] = match;
    
    return {
      rpcMethod,
      targetAddress: targetAddress || '0x0000000000000000000000000000000000000000',
      chainId: chainId ? parseInt(chainId) : null,
      parameters: this.parseQueryString(queryString)
    };
  }

  /**
   * Parses query string parameters, handling bracket notation for nested objects/arrays
   * @param {string} queryString - The query string to parse
   * @returns {Object} Parsed parameters object
   */
  parseQueryString(queryString) {
    if (!queryString) return {};
    
    const params = {};
    const pairs = queryString.split('&');
    
    for (const pair of pairs) {
      const [key, value] = pair.split('=');
      const decodedKey = decodeURIComponent(key);
      const decodedValue = decodeURIComponent(value);
      
      // Handle bracket notation for nested objects/arrays
      const bracketMatch = decodedKey.match(/^(.+)\[([^\]]+)\]$/);
      if (bracketMatch) {
        const [, baseKey, index] = bracketMatch;
        if (!params[baseKey]) {
          params[baseKey] = isNaN(index) ? {} : [];
        }
        params[baseKey][isNaN(index) ? index : parseInt(index)] = decodedValue;
      } else {
        params[decodedKey] = decodedValue;
      }
    }
    
    return params;
  }

  /**
   * Converts the parsed URI to a JSON-RPC request
   * @returns {Object} JSON-RPC request object
   */
  toRPCRequest() {
    const { rpcMethod, parameters } = this.parsed;
    
    if (rpcMethod === 'multiRequest') {
      const requestsB64 = parameters.requests_b64;
      if (!requestsB64) {
        throw new Error('multiRequest requires requests_b64 parameter');
      }
      return JSON.parse(atob(requestsB64));
    }
    
    return {
      method: rpcMethod,
      params: [parameters]
    };
  }

  /**
   * Validates the URI format and parameters
   * @returns {boolean} True if valid, throws error if invalid
   */
  validate() {
    // Basic format validation
    if (!this.uri.startsWith('ethereum:')) {
      throw new Error('URI must start with "ethereum:"');
    }

    // RPC method validation
    if (!this.parsed.rpcMethod) {
      throw new Error('RPC method is required');
    }

    // Chain ID validation
    if (this.parsed.chainId && (this.parsed.chainId < 1 || this.parsed.chainId > 999999999)) {
      throw new Error('Invalid chain ID');
    }

    // Address validation for target address
    if (this.parsed.targetAddress !== '0x0000000000000000000000000000000000000000' && 
        this.parsed.targetAddress !== 'CURRENT_ACCOUNT') {
      if (!this.isValidAddress(this.parsed.targetAddress)) {
        throw new Error('Invalid target address');
      }
    }

    return true;
  }

  /**
   * Validates Ethereum address format
   * @param {string} address - Address to validate
   * @returns {boolean} True if valid address
   */
  isValidAddress(address) {
    return /^0x[a-fA-F0-9]{40}$/.test(address);
  }

  /**
   * Gets the parsed components as a readable object
   * @returns {Object} Parsed components
   */
  getComponents() {
    return {
      ...this.parsed,
      originalUri: this.uri
    };
  }
}

/**
 * Utility function to create an Ethereum Intent URI
 * @param {Object} options - URI creation options
 * @returns {string} Formatted Ethereum Intent URI
 */
function createEthereumIntentURI(options) {
  const {
    rpcMethod,
    targetAddress = '0x0000000000000000000000000000000000000000',
    chainId,
    parameters = {}
  } = options;

  if (!rpcMethod) {
    throw new Error('RPC method is required');
  }

  let uri = `ethereum:${rpcMethod}-${targetAddress}`;
  
  if (chainId) {
    uri += `@${chainId}`;
  }

  if (Object.keys(parameters).length > 0) {
    const queryString = Object.entries(parameters)
      .map(([key, value]) => {
        if (typeof value === 'object') {
          // Handle nested objects/arrays
          return Object.entries(value)
            .map(([nestedKey, nestedValue]) => 
              `${encodeURIComponent(key)}[${encodeURIComponent(nestedKey)}]=${encodeURIComponent(nestedValue)}`
            )
            .join('&');
        }
        return `${encodeURIComponent(key)}=${encodeURIComponent(value)}`;
      })
      .join('&');
    
    uri += `?${queryString}`;
  }

  return uri;
}

/**
 * Utility function to create a multi-request URI
 * @param {Array} requests - Array of RPC requests
 * @param {number} chainId - Optional chain ID
 * @returns {string} Multi-request URI
 */
function createMultiRequestURI(requests, chainId = null) {
  const requestsB64 = btoa(JSON.stringify(requests));
  
  return createEthereumIntentURI({
    rpcMethod: 'multiRequest',
    chainId,
    parameters: {
      requests_b64: requestsB64
    }
  });
}

// Export for use in different environments
if (typeof module !== 'undefined' && module.exports) {
  module.exports = {
    EthereumIntentURI,
    createEthereumIntentURI,
    createMultiRequestURI
  };
} else if (typeof window !== 'undefined') {
  window.EthereumIntentURI = EthereumIntentURI;
  window.createEthereumIntentURI = createEthereumIntentURI;
  window.createMultiRequestURI = createMultiRequestURI;
}

// Example usage:
/*
// Parse a URI
const uri = new EthereumIntentURI('ethereum:eth_sendTransaction-0x0000000000000000000000000000000000000000@1?from=CURRENT_ACCOUNT&to=0x742d35Cc6634C0532925a3b8D4C9db96C4b4d8b6&value=0xde0b6b3a7640000');
console.log(uri.getComponents());
console.log(uri.toRPCRequest());

// Create a URI
const newUri = createEthereumIntentURI({
  rpcMethod: 'eth_sendTransaction',
  chainId: 1,
  parameters: {
    from: 'CURRENT_ACCOUNT',
    to: '0x742d35Cc6634C0532925a3b8D4C9db96C4b4d8b6',
    value: '0xde0b6b3a7640000'
  }
});
console.log(newUri);
*/ 
