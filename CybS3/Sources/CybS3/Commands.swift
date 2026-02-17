import ArgumentParser
import Foundation

/// The main entry point for the CybS3 Command Line Interface.
///
/// CybS3 provides an S3-compatible object storage browser with client-side encryption capabilities.
struct CybS3CLI: AsyncParsableCommand {
}

extension CybS3CLI {
    static let configuration = CommandConfiguration(
        commandName: "cybs3",
        abstract: "S3 Compatible Object Storage Browser",
        subcommands: [
            CoreCommands.self,
            BucketCommands.self,
            FileCommands.self,
            ServerCommands.self,
            PerformanceCommands.self,
            Folders.self,
            Compliance.self,
            Health.self,
            Keys.self,
            MultiCloud.self,
            Test.self,
            Vaults.self,
            BackupCommands.self,
            Chaos.self,
        ]
    )
}
