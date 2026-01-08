enum LambdaError: Error {
    case cantAccessMusicAPISecret(rootCause: Error)
    case noAuthenticationToken(msg: String)
}
