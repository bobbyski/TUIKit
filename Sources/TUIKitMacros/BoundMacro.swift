import SwiftCompilerPlugin
import SwiftDiagnostics
import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros

/// `@Bound var name = ""` generates a `$name` projection returning a
/// `Binding<String>` to the property, so a control reads `field.bind(model.$name)`.
///
/// The type comes from an explicit annotation, or is inferred from a literal
/// initializer (`""`→`String`, `0`→`Int`, `0.0`→`Double`, `false`→`Bool`).
/// Non-literal types (e.g. `Date`) need an annotation: `@Bound var due: Date`.
/// Requires a reference-type (class) enclosing scope so the setter writes back
/// through `self`.
public struct BoundMacro: PeerMacro {
    public static func expansion(
        of node: AttributeSyntax,
        providingPeersOf declaration: some DeclSyntaxProtocol,
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        guard
            let variable = declaration.as(VariableDeclSyntax.self),
            let binding = variable.bindings.first,
            let pattern = binding.pattern.as(IdentifierPatternSyntax.self)
        else {
            throw MacroError.message("@Bound can only be applied to a stored property")
        }

        let typeName: String

        if let annotated = binding.typeAnnotation?.type {
            typeName = annotated.trimmedDescription
        } else if let inferred = inferredTypeName(from: binding.initializer?.value) {
            typeName = inferred
        } else {
            throw MacroError.message(
                "@Bound needs an explicit type or a literal initializer, e.g. `@Bound var name = \"\"` or `@Bound var due: Date`"
            )
        }

        let name = pattern.identifier.text

        let projection: DeclSyntax =
            """
            var $\(raw: name): Binding<\(raw: typeName)> {
                Binding(get: { self.\(raw: name) }, set: { self.\(raw: name) = $0 })
            }
            """

        return [projection]
    }

    // Infers a Swift type name from a literal initializer expression.
    private static func inferredTypeName(from expression: ExprSyntax?) -> String? {
        guard let expression else { return nil }

        if expression.is(StringLiteralExprSyntax.self) { return "String" }
        if expression.is(IntegerLiteralExprSyntax.self) { return "Int" }
        if expression.is(FloatLiteralExprSyntax.self) { return "Double" }
        if expression.is(BooleanLiteralExprSyntax.self) { return "Bool" }

        return nil
    }
}

// A simple error carrying a message to the compiler.
enum MacroError: Error, CustomStringConvertible {
    case message(String)
    var description: String {
        switch self { case .message(let text): return text }
    }
}

@main
struct TUIKitMacrosPlugin: CompilerPlugin {
    let providingMacros: [Macro.Type] = [BoundMacro.self]
}
