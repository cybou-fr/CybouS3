import ArgumentParser
import CybS3Lib
import Foundation

/// Bucket management commands
struct BucketCommands: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "buckets",
        abstract: "Manage S3 buckets",
        subcommands: [
            Create.self,
            Delete.self,
            List.self,
        ]
    )

    struct Create: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "create",
            abstract: "Create a new bucket"
        )

        @OptionGroup var options: GlobalOptions

        @Argument(help: "Bucket name")
        var bucketName: String

        func run() async throws {
            do {
                let (client, _, _, vaultName, _) = try GlobalOptions.createClient(
                    options, overrideBucket: bucketName)
                defer { Task { try? await client.shutdown() } }
                ConsoleUI.dim("Using vault: \(vaultName ?? "default")")
                try await client.createBucket(name: bucketName)
                ConsoleUI.success("Created bucket: \(bucketName)")
            } catch let error as S3Error {
                ConsoleUI.error(error.localizedDescription)
                throw ExitCode.failure
            }
        }
    }

    struct Delete: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "delete",
            abstract: "Delete an empty bucket"
        )

        @OptionGroup var options: GlobalOptions

        @Argument(help: "Bucket name to delete")
        var bucketName: String

        @Flag(name: .shortAndLong, help: "Force delete without confirmation")
        var force: Bool = false

        func run() async throws {
            if !force {
                ConsoleUI.warning("You are about to delete bucket '\(bucketName)'. This cannot be undone.")
                guard InteractionService.confirm(message: "Are you sure?", defaultValue: false) else {
                    ConsoleUI.info("Operation cancelled.")
                    return
                }
            }

            do {
                let (client, _, _, vaultName, _) = try GlobalOptions.createClient(options)
                defer { Task { try? await client.shutdown() } }
                ConsoleUI.dim("Using vault: \(vaultName ?? "default")")
                try await client.deleteBucket(name: bucketName)
                ConsoleUI.success("Deleted bucket: \(bucketName)")
            } catch let error as S3Error {
                ConsoleUI.error(error.localizedDescription)
                throw ExitCode.failure
            }
        }
    }

    struct List: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "list",
            abstract: "List all buckets"
        )

        @OptionGroup var options: GlobalOptions

        @Flag(name: .long, help: "Output as JSON")
        var json: Bool = false

        func run() async throws {
            let (client, _, _, vaultName, _) = try GlobalOptions.createClient(options)
            defer { Task { try? await client.shutdown() } }
            if !json {
                print("Using vault: \(vaultName ?? "default")")
            }
            let buckets = try await client.listBuckets()

            if json {
                let encoder = JSONEncoder()
                encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                let data = try encoder.encode(["buckets": buckets])
                print(String(data: data, encoding: .utf8) ?? "[]")
            } else {
                print("Buckets:")
                for bucket in buckets {
                    print("  \(bucket)")
                }
            }
        }
    }
}