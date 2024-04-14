import AWSLambdaDeploymentDescriptor

DeploymentDescriptor {
  "Maxi80 iOS app backend service"

  // Create a lambda function exposed through a REST API
  Function(name: "Maxi80Lambda") {
    "This function provides the backend to the Maxi80 iOS app"
    EventSources { HttpApi() }
    EnvironmentVariables {
      [
        "LOG_LEVEL": "debug",
        "SECRETS": "maxi80_secrets"
      ]
    }
  }
}