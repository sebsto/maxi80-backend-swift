import Maxi80Lambda

// TODO: change region to actual prod deployment
let sm = SecretsManager(secretName: "Maxi80_AppleMusicAPI", region: "us-east-1")

// secret is an instance of Secret() and it's created in a separate file not saved to git
let arn = try await sm.storeSecret(secret: secret)
print(arn)