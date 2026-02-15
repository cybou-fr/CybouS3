import Foundation
import ArgumentParser
import SwiftBIP39
import CybS3Lib

extension CybS3 {
    struct Keys: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "keys",
            abstract: "Manage encryption keys and mnemonics",
            subcommands: [
                Create.self,
                Validate.self,
                Rotate.self
            ]
        )
    }
}

extension CybS3.Keys {
    /// Command to generate a new 12-word mnemonic phrase.
    struct Create: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "create",
            abstract: "Generate a new 12-word mnemonic phrase"
        )
        
        func run() async throws {
            do {
                let mnemonic = try BIP39.generateMnemonic(wordCount: .twelve, language: .english)
                print("Your new mnemonic phrase (KEEP THIS SAFE!):")
                print("------------------------------------------------")
                print(mnemonic.joined(separator: " "))
                print("------------------------------------------------")
                
                // Verify the user captured the mnemonic correctly
                print("\n⚠️  Please save your mnemonic safely before continuing.")
                let confirmed = InteractionService.verifyMnemonicEntry(mnemonic: mnemonic)
                
                if !confirmed {
                    throw CLIError.operationAborted(reason: "Mnemonic verification failed. Please try again with 'cybs3 keys create'.")
                }
                
                print("\n✅ Your mnemonic has been verified and is ready to use.")
                print("💡 Run 'cybs3 login' to store it securely in Keychain.")
            } catch {
                print("Error generating mnemonic: \(error)")
                throw ExitCode.failure
            }
        }
    }
    
    /// Command to validate a mnemonic phrase.
    struct Validate: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "validate",
            abstract: "Validate a mnemonic phrase"
        )
        
        @Argument(help: "The mnemonic phrase to validate (12 words)")
        var words: [String]
        
        func run() async throws {
            do {
                try BIP39.validate(mnemonic: words, language: .english)
                print("✅ Mnemonic is valid.")
            } catch BIP39.Error.invalidWordCount {
                print("❌ Invalid word count. Expected 12 words.")
                throw ExitCode.failure
            } catch BIP39.Error.invalidWord(let word) {
                print("❌ Invalid word found: '\(word)' appears to be not in the wordlist.")
                throw ExitCode.failure
            } catch BIP39.Error.invalidChecksum {
                print("❌ Invalid checksum. The phrase is not valid.")
                throw ExitCode.failure
            } catch {
                print("❌ Error: \(error)")
                throw ExitCode.failure
            }
        }
    }
    
    /// Command to rotate the Master Key (Mnemonic) while maintaining access to encrypted data.
    struct Rotate: AsyncParsableCommand {
         static let configuration = CommandConfiguration(
             commandName: "rotate",
             abstract: "Rotate your Mnemonic (Master Key) while preserving data access"
         )
         
         func run() async throws {
             ConsoleUI.header("Key Rotation Process")
             ConsoleUI.info("Step 1: Authenticate with CURRENT Mnemonic")
             
             let oldMnemonic: [String]
             do {
                 oldMnemonic = try InteractionService.promptForMnemonic(purpose: "authenticate (Current Mnemonic)")
             } catch {
                 ConsoleUI.error("Authentication failed: \(error.localizedDescription)")
                 throw ExitCode.failure
             }
             
             ConsoleUI.info("Step 2: Enter (or Generate) NEW Mnemonic")
             print("Do you want to (G)enerate a new one or (E)nter one manually? [G/e]")
             let choice = readLine()?.lowercased() ?? "g"
             
             let newMnemonic: [String]
             if choice.starts(with: "e") {
                 do {
                     newMnemonic = try InteractionService.promptForMnemonic(purpose: "set as NEW Mnemonic")
                 } catch {
                     ConsoleUI.error("Failed to process mnemonic: \(error.localizedDescription)")
                     throw ExitCode.failure
                 }
             } else {
                 do {
                     newMnemonic = try BIP39.generateMnemonic(wordCount: .twelve, language: .english)
                     ConsoleUI.header("YOUR NEW MNEMONIC (WRITE THIS DOWN!)")
                     print(newMnemonic.joined(separator: " "))
                     ConsoleUI.dim("Store this securely. You will need it to access your encrypted data.")
                     ConsoleUI.info("Press Enter once you have saved it.")
                     _ = readLine()
                 } catch {
                     ConsoleUI.error("Error generating mnemonic: \(error.localizedDescription)")
                     throw ExitCode.failure
                 }
             }
             
             // Confirmation before rotation
             ConsoleUI.warning("Key rotation will change your master key but preserve access to all encrypted data.")
             guard InteractionService.confirm(message: "Do you want to proceed with key rotation?", defaultValue: false) else {
                 ConsoleUI.info("Key rotation cancelled.")
                 return
             }
             
             do {
                 try StorageService.rotateKey(oldMnemonic: oldMnemonic, newMnemonic: newMnemonic)
                 ConsoleUI.success("Key Rotation Successful!")
                 ConsoleUI.info("You MUST use your NEW mnemonic for all future operations.")
             } catch {
                 ConsoleUI.error("Error rotating key: \(error.localizedDescription)")
                 throw ExitCode.failure
             }
         }
     }
}
