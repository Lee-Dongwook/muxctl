import Foundation
import SwiftOperators
import SwiftParser
import SwiftSyntax

public struct Interpreter: Sendable {
    private let expressions = ExpressionEvaluator()

    public init() {}

    public func parse(_ source: String) -> ParsedProgram {
        onLargeStack {
            let parsed = Parser.parse(source: source)
            let file = (try? OperatorTable.standardOperators.foldAll(parsed))?
                .as(SourceFileSyntax.self) ?? parsed
            return ParsedProgram(file: file)
        }
    }

    public func evaluate(_ program: ParsedProgram, state: [String: SwiftValue] = [:]) -> RenderNode? {
        onLargeStack {
            let env = EvalEnvironment(values: state)
            self.registerFunctions(program.file.statements, env)
            self.bindTopLevelVariables(program.file.statements, env)

            for item in program.file.statements {
                if let expr = item.item.as(ExprSyntax.self), let node = self.evalView(expr, env) {
                    return env.budget.nodesExceeded ? nil : node
                }
            }

            return nil
        }
    }

    public func evaluate(_ source: String, state: [String: SwiftValue] = [:]) -> RenderNode? {
        evaluate(parse(source), state: state)
    }

    private func onLargeStack<T: Sendable>(_ work: @escaping @Sendable () -> T) -> T {
        let box = LargeStackResultBox<T>()
        let done = DispatchSemaphore(value: 0)
        let worker = Thread {
            box.value = work()
            done.signal()
        }

        worker.stackSize = 16 * 1024 * 1024
        worker.start()
        done.wait()
        return box.value!
    }

    private func registerFunctions(_ items: CodeBlockItemListSyntax, _ env: EvalEnvironment) {
        for item in items {
            if let fn = item.item.as(FunctionDeclSyntax.self) {
                env.defineFunction(fn.name.text, fn)
            }
        }
    }

    private func bindTopLevelVariables(_ items: CodeBlockItemListSyntax, _ env: EvalEnvironment) {
        var pending = items.compactMap { $0.item.as(VariableDeclSyntax.self) }
            .flatMap { Array($0.bindings) }
        
        while !pending.isEmpty {
            let previousCount = pending.count
            var pendingNames = Set(pending.compactMap {
                $0.pattern.as(IdentifierPatternSyntax.self)?.identifier.text
            })
            pending.removeAll { binding in
                guard let name = binding.pattern.as(IdentifierPatternSyntax.self)?.identifier.text,
                      let initializer = binding.initializer else { return true }
                
                let result = env.trackingUnresolvedNames(pendingnames) {
                    expressions.eval(initializer.value, env)
                }

                guard !result.readUnresolvedName, let value = result.value else { return false }
                env.define(name, value)
                pendingNames.remove(name)
                return true
            }

            if pending.count == previousCount { break }
        }

        env.maskUnresolvedNames(Set(pending.compactMap {
            $0.pattern.as(IdentifierPatternSyntax.self)?.identifier.text
        }))
    }
}
