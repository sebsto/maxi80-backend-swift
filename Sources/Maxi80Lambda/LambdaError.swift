enum LambdaError: Error {
	case noAuthenticationToken(msg: String)
	case noTokenFactory(msg: String)
}