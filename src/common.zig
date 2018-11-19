pub fn @"align"(address: var, alignment: var) @typeOf(address + alignment) {
    const rem = address % alignment;
    const result = address + (alignment - rem);

    return result;
}
