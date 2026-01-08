import ArgumentParser
import Logging
import Maxi80Backend

@main
struct CLI: AsyncParsableCommand {

    @OptionGroup var globalOptions: GlobalOptions

    // Customize the command's help and subcommands by implementing the
    // `configuration` property.
    nonisolated static let configuration = CommandConfiguration(
        commandName: "Maxi80CLI",

        // Optional abstracts and discussions are used for help output.
        abstract: "A utility to download and install interact with Maxi80 backend API",

        // Pass an array to `subcommands` to set up a nested tree of subcommands.
        // With language support for type-level introspection, this could be
        // provided by automatically finding nested `ParsableCommand` types.
        subcommands: [
            StoreSecrets.self, GetSecrets.self,
        ]

        // A default subcommand, when provided, is automatically selected if a
        // subcommand is not given on the command line.
        // defaultSubcommand: List.self)
    )

}
