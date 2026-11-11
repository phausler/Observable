import SwiftCompilerPlugin
import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros

@main
struct ObservationPlugin: CompilerPlugin {
    let providingMacros: [Macro.Type] = [
        ObservationTrackedMacro.self,
        ObservationIgnoredMacro.self,
        ObservableMacro.self,
        ObservationDerivedMacro.self,
    ]
}
