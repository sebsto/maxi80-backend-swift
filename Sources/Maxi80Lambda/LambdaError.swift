enum LambdaError: Error {
	case noAuthenticationToken(msg: String)
}