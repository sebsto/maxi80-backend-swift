import ArgumentParser
import Logging
import Maxi80Backend

struct StoreSecrets: AsyncParsableCommand {

    @OptionGroup var globalOptions: GlobalOptions

    public func run() async throws {
        let logger = GlobalOptions.logger(verbose: globalOptions.verbose)
        let sm = try SecretsManager<AppleMusicSecret>(
            region: globalOptions.region,
            awsProfileName: globalOptions.profile,
            logger: logger
        )

        // Secret() lives in a separate file not saved to git
        let arn = try await sm.storeSecret(secret: Secret.get(), secretName: globalOptions.secretName)
        print("✅ your secret is stored. Arn = \(arn)")
    }
}

struct GetSecrets: AsyncParsableCommand {

    @OptionGroup var globalOptions: GlobalOptions

    public func run() async throws {

        let logger = GlobalOptions.logger(verbose: globalOptions.verbose)
        let sm = try SecretsManager<AppleMusicSecret>(
            region: globalOptions.region,
            awsProfileName: globalOptions.profile,
            logger: logger
        )

        // Secret() lives in a separate file not saved to git
        let secret = try await sm.getSecret(secretName: globalOptions.secretName)
        print("✅ your secret is \(secret)")
    }
}
