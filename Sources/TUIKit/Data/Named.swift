public extension TUIView {
    /// Sets this view's data-layer `name` and returns it, for chaining.
    ///
    /// ```swift
    /// TextField().named("email").bind($form.email)
    /// ```
    ///
    /// - Parameter name: The name used by dotted-path lookup and form I/O.
    /// - Returns: `self`.
    @discardableResult
    func named(_ name: String) -> Self {
        self.name = name
        return self
    }

    /// Finds the deepest-first descendant satisfying a predicate (excludes
    /// `self`, includes hidden views — data ignores visibility).
    ///
    /// - Parameter predicate: The match test.
    /// - Returns: The first matching descendant, or `nil`.
    func firstDescendant(where predicate: (TUIView) -> Bool) -> TUIView? {
        for child in subviews {
            if predicate(child) {
                return child
            }

            if let found = child.firstDescendant(where: predicate) {
                return found
            }
        }

        return nil
    }

    /// Resolves a dotted `name` path to a descendant view.
    ///
    /// Each `.`-separated segment names a descendant to descend into, so
    /// `"address.city"` finds a `city`-named control inside an `address`-named
    /// container at any depth. First match wins per segment.
    ///
    /// - Parameter path: A dotted name path.
    /// - Returns: The addressed view, or `nil` if any segment is unresolved.
    func view(named path: String) -> TUIView? {
        let segments = path.split(separator: ".").map(String.init)

        guard !segments.isEmpty else {
            return nil
        }

        var current: TUIView = self

        for segment in segments {
            guard let next = current.firstDescendant(where: { $0.name == segment }) else {
                return nil
            }

            current = next
        }

        return current
    }

    /// Reads the value of the control at a dotted path.
    ///
    /// - Parameter path: A dotted name path.
    /// - Returns: The control's value.
    /// - Throws: `ValueError.notFound` or `.notAValueControl`.
    func value(for path: String) throws -> Any {
        guard let view = view(named: path) else {
            throw ValueError.notFound(path: path)
        }

        guard let control = view as? ValueControl else {
            throw ValueError.notAValueControl(path: path)
        }

        return control.anyValue()
    }

    /// Sets the value of the control at a dotted path (silently).
    ///
    /// - Parameters:
    ///   - value: The new value.
    ///   - path: A dotted name path.
    /// - Throws: `ValueError.notFound`, `.notAValueControl`, or `.typeMismatch`.
    func setValue(_ value: Any, for path: String) throws {
        guard let view = view(named: path) else {
            throw ValueError.notFound(path: path)
        }

        guard let control = view as? ValueControl else {
            throw ValueError.notAValueControl(path: path)
        }

        try control.setAnyValue(value)
    }

    /// Dumps every named `ValueControl` in the subtree, keyed by its full
    /// dotted path (the join of ancestor names).
    ///
    /// - Returns: A `[dotted-path: value]` snapshot.
    func formValues() -> [String: Any] {
        var result: [String: Any] = [:]
        collectFormValues(prefix: "", into: &result)
        return result
    }

    /// Applies a `[dotted-path: value]` dictionary to the subtree, silently.
    ///
    /// Unknown paths and non-value nodes are ignored; type mismatches throw.
    ///
    /// - Parameter values: The values to apply.
    /// - Returns: The paths that were applied.
    /// - Throws: `ValueError.typeMismatch` from a control.
    @discardableResult
    func applyValues(_ values: [String: Any]) throws -> [String] {
        var applied: [String] = []

        for (path, value) in values {
            guard let view = view(named: path), let control = view as? ValueControl else {
                continue
            }

            try control.setAnyValue(value)
            applied.append(path)
        }

        return applied
    }

    // Accumulates named values, extending the dotted prefix at each named node.
    private func collectFormValues(prefix: String, into result: inout [String: Any]) {
        for child in subviews {
            let path = child.name.map { prefix.isEmpty ? $0 : prefix + "." + $0 } ?? prefix

            if child.name != nil, let control = child as? ValueControl {
                result[path] = control.anyValue()
            }

            child.collectFormValues(prefix: path, into: &result)
        }
    }
}
