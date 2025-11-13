declare module 'canonical-json' {
  // Declare the type of the default export 'canonicalize'
  // It takes any JS value and returns a string.
  function canonicalize(obj: unknown): string;
  // Use export default for default export
  export default canonicalize;
} 