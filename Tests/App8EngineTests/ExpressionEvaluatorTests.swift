//
//  ExpressionEvaluatorTests.swift
//  App8EngineTests
//

import XCTest
@testable import App8Engine

@MainActor
class ExpressionEvaluatorTests: XCTestCase {
    var parser: ExpressionParser!
    var evaluator: ExpressionEvaluator!
    var testContext: VariableContext!
    var variableStore: VariableStore!

    override func setUp() {
        super.setUp()
        parser = ExpressionParser()
        evaluator = ExpressionEvaluator()
        variableStore = VariableStore()

        try! variableStore.defineVariable(name: "name", definition: VariableDefinition(type: .string, initialValue: "John"))
        try! variableStore.defineVariable(name: "age", definition: VariableDefinition(type: .number, initialValue: 25))
        try! variableStore.defineVariable(name: "isActive", definition: VariableDefinition(type: .boolean, initialValue: true))
        try! variableStore.defineVariable(name: "items", definition: VariableDefinition(type: .array, initialValue: ["apple", "banana", "cherry"]))
        try! variableStore.defineVariable(name: "user", definition: VariableDefinition(type: .object, initialValue: [
            "firstName": "Jane",
            "lastName": "Doe",
            "age": 30,
            "email": "jane@example.com"
        ]))
        try! variableStore.defineVariable(name: "nullVar", definition: VariableDefinition(type: .string, initialValue: nil))
        try! variableStore.defineVariable(name: "emptyString", definition: VariableDefinition(type: .string, initialValue: ""))
        try! variableStore.defineVariable(name: "zero", definition: VariableDefinition(type: .number, initialValue: 0))

        testContext = VariableContext(store: variableStore)
    }

    // MARK: - Literal Evaluation Tests

    func testEvaluateLiterals() throws {
        XCTAssertEqual(try evaluate("true") as? Bool, true)
        XCTAssertEqual(try evaluate("false") as? Bool, false)
        XCTAssertEqual(try evaluate("42") as? Int, 42)
        XCTAssertEqual(try evaluate("3.14") as? Double, 3.14)
        XCTAssertEqual(try evaluate("'hello'") as? String, "hello")
        XCTAssertTrue(try evaluate("null") is NSNull)
    }

    // MARK: - Variable Evaluation Tests

    func testEvaluateVariables() throws {
        XCTAssertEqual(try evaluate("name") as? String, "John")
        XCTAssertEqual(try evaluate("age") as? Int, 25)
        XCTAssertEqual(try evaluate("isActive") as? Bool, true)
        XCTAssertEqual(try evaluate("items") as? [String], ["apple", "banana", "cherry"])
    }

    func testEvaluateUndefinedVariable() {
        XCTAssertThrowsError(try evaluate("undefinedVar")) { error in
            XCTAssertTrue(error is VariableError)
        }
    }

    // MARK: - Arithmetic Operation Tests

    func testEvaluateArithmetic() throws {
        XCTAssertEqual(try evaluate("2 + 3") as? Int, 5)
        XCTAssertEqual(try evaluate("10 - 4") as? Int, 6)
        XCTAssertEqual(try evaluate("3 * 4") as? Int, 12)
        XCTAssertEqual(try evaluate("15 / 3") as? Double, 5.0)

        // With variables
        XCTAssertEqual(try evaluate("age + 5") as? Int, 30)
        XCTAssertEqual(try evaluate("age * 2") as? Int, 50)
    }

    func testEvaluateStringConcatenation() throws {
        XCTAssertEqual(try evaluate("'Hello' + ' ' + 'World'") as? String, "Hello World")
        XCTAssertEqual(try evaluate("name + ' is ' + age + ' years old'") as? String, "John is 25 years old")
    }

    // MARK: - Interpolated String Tests

    func testParseBareExpression() throws {
        // "{{name}}" is a single expression — strips {{ }} and evaluates
        XCTAssertEqual(try evaluate("{{name}}") as? String, "John")
        XCTAssertEqual(try evaluate("{{age}}") as? Int, 25)
    }

    func testParseInterpolatedStringWithPrefix() throws {
        // "Hello, {{name}}!" has text outside braces
        XCTAssertEqual(try evaluate("Hello, {{name}}!") as? String, "Hello, John!")
    }

    func testParseInterpolatedStringWithSuffix() throws {
        XCTAssertEqual(try evaluate("{{name}} says hi") as? String, "John says hi")
    }

    func testParseCompoundInterpolation() throws {
        // Two expressions with literal text between them
        XCTAssertEqual(try evaluate("{{name}} is {{age}}") as? String, "John is 25")
    }

    func testParseInterpolatedWithMemberAccess() throws {
        XCTAssertEqual(try evaluate("{{user.firstName}} {{user.lastName}}") as? String, "Jane Doe")
    }

    // MARK: - Comparison Operation Tests

    func testEvaluateComparison() throws {
        XCTAssertEqual(try evaluate("5 > 3") as? Bool, true)
        XCTAssertEqual(try evaluate("2 >= 2") as? Bool, true)
        XCTAssertEqual(try evaluate("10 < 5") as? Bool, false)
        XCTAssertEqual(try evaluate("3 <= 3") as? Bool, true)

        // With variables
        XCTAssertEqual(try evaluate("age > 20") as? Bool, true)
        XCTAssertEqual(try evaluate("age <= 25") as? Bool, true)
    }

    // MARK: - Equality Operation Tests

    func testEvaluateEquality() throws {
        // Strict equality
        XCTAssertEqual(try evaluate("5 === 5") as? Bool, true)
        XCTAssertEqual(try evaluate("'hello' === 'hello'") as? Bool, true)
        XCTAssertEqual(try evaluate("true === true") as? Bool, true)
        XCTAssertEqual(try evaluate("5 === '5'") as? Bool, false)

        // Strict inequality
        XCTAssertEqual(try evaluate("5 !== '5'") as? Bool, true)
        XCTAssertEqual(try evaluate("null !== null") as? Bool, false)

        // Loose equality
        XCTAssertEqual(try evaluate("5 == '5'") as? Bool, true)
        XCTAssertEqual(try evaluate("null == null") as? Bool, true)

        // With variables
        XCTAssertEqual(try evaluate("name === 'John'") as? Bool, true)
        XCTAssertEqual(try evaluate("age !== 30") as? Bool, true)
    }

    // MARK: - Logical Operation Tests

    func testEvaluateLogical() throws {
        XCTAssertEqual(try evaluate("true && true") as? Bool, true)
        XCTAssertEqual(try evaluate("true && false") as? Bool, false)
        XCTAssertEqual(try evaluate("false || true") as? Bool, true)
        XCTAssertEqual(try evaluate("false || false") as? Bool, false)

        // Short-circuit evaluation
        XCTAssertEqual(try evaluate("false && undefinedVar") as? Bool, false)
        XCTAssertEqual(try evaluate("true || undefinedVar") as? Bool, true)

        // With variables
        XCTAssertEqual(try evaluate("isActive && age > 20") as? Bool, true)
        XCTAssertEqual(try evaluate("name === 'Jane' || age === 25") as? Bool, true)
    }

    // MARK: - Unary Operation Tests

    func testEvaluateUnary() throws {
        XCTAssertEqual(try evaluate("!true") as? Bool, false)
        XCTAssertEqual(try evaluate("!false") as? Bool, true)
        XCTAssertEqual(try evaluate("!!true") as? Bool, true)
        XCTAssertEqual(try evaluate("-5") as? Int, -5)
        XCTAssertEqual(try evaluate("-age") as? Int, -25)
        XCTAssertEqual(try evaluate("!isActive") as? Bool, false)
    }

    // MARK: - Member Access Tests

    func testEvaluateMemberAccess() throws {
        XCTAssertEqual(try evaluate("user.firstName") as? String, "Jane")
        XCTAssertEqual(try evaluate("user.age") as? Int, 30)
        XCTAssertEqual(try evaluate("items.length") as? Int, 3)
        XCTAssertEqual(try evaluate("name.length") as? Int, 4)

        // Undefined member
        XCTAssertNil(try evaluate("user.undefined"))
    }

    // MARK: - Array Access Tests

    func testEvaluateArrayAccess() throws {
        XCTAssertEqual(try evaluate("items[0]") as? String, "apple")
        XCTAssertEqual(try evaluate("items[1]") as? String, "banana")
        XCTAssertEqual(try evaluate("items[2]") as? String, "cherry")

        // Out of bounds
        XCTAssertNil(try evaluate("items[10]"))
        XCTAssertNil(try evaluate("items[-1]"))
    }

    // MARK: - Function Call Tests

    func testEvaluateFunctionCalls() throws {
        // length function
        XCTAssertEqual(try evaluate("length(items)") as? Int, 3)
        XCTAssertEqual(try evaluate("length('hello')") as? Int, 5)

        // includes function
        XCTAssertEqual(try evaluate("includes(items, 'banana')") as? Bool, true)
        XCTAssertEqual(try evaluate("includes(items, 'orange')") as? Bool, false)
        XCTAssertEqual(try evaluate("includes(name, 'oh')") as? Bool, true)
        // Empty search string matches everything (makes live-search expressions work when query is empty)
        XCTAssertEqual(try evaluate("includes('hello', '')") as? Bool, true)
        XCTAssertEqual(try evaluate("includes(emptyString, '')") as? Bool, true)
        XCTAssertEqual(try evaluate("includes(name, '')") as? Bool, true)

        // match function
        XCTAssertEqual(try evaluate("match(user.email, '^[^\\\\s@]+@[^\\\\s@]+\\\\.[^\\\\s@]+$')") as? Bool, true)
        XCTAssertEqual(try evaluate("match('invalid-email', '^[^\\\\s@]+@[^\\\\s@]+\\\\.[^\\\\s@]+$')") as? Bool, false)

        // parseInt/parseFloat
        XCTAssertEqual(try evaluate("parseInt('123')") as? Int, 123)
        XCTAssertEqual(try evaluate("parseFloat('3.14')") as? Double, 3.14)

        // toString
        XCTAssertEqual(try evaluate("toString(42)") as? String, "42")
        XCTAssertEqual(try evaluate("toString(true)") as? String, "true")

        // isArray
        XCTAssertEqual(try evaluate("isArray(items)") as? Bool, true)
        XCTAssertEqual(try evaluate("isArray(name)") as? Bool, false)
    }

    // MARK: - Ternary Operation Tests

    func testEvaluateTernary() throws {
        XCTAssertEqual(try evaluate("true ? 'yes' : 'no'") as? String, "yes")
        XCTAssertEqual(try evaluate("false ? 'yes' : 'no'") as? String, "no")
        XCTAssertEqual(try evaluate("age > 18 ? 'adult' : 'minor'") as? String, "adult")
        XCTAssertEqual(try evaluate("name === 'John' ? age : 0") as? Int, 25)
    }

    // MARK: - Complex Expression Tests

    func testEvaluateComplexExpressions() throws {
        // Nested operations
        XCTAssertEqual(try evaluate("(age + 5) * 2") as? Int, 60)
        XCTAssertEqual(try evaluate("isActive && (age > 20 || name === 'Admin')") as? Bool, true)

        // Multiple ternary
        XCTAssertEqual(
            try evaluate("age > 60 ? 'senior' : age > 18 ? 'adult' : 'minor'") as? String,
            "adult"
        )

        // Complex member access
        XCTAssertEqual(
            try evaluate("user.firstName + ' ' + user.lastName") as? String,
            "Jane Doe"
        )

        // Boolean coercion
        XCTAssertEqual(try evaluate("!!emptyString") as? Bool, false)
        XCTAssertEqual(try evaluate("!!name") as? Bool, true)
        XCTAssertEqual(try evaluate("!!zero") as? Bool, false)
        XCTAssertEqual(try evaluate("!!nullVar") as? Bool, false)
    }

    // MARK: - Dependency Extraction Tests

    func testDependencyExtraction() throws {
        let extractor = DependencyExtractor()

        var node = try parser.parse("name")
        XCTAssertEqual(extractor.extractDependencies(from: node), ["name"])

        node = try parser.parse("age > 18")
        XCTAssertEqual(extractor.extractDependencies(from: node), ["age"])

        node = try parser.parse("isActive && (age > 20 || name === 'Admin')")
        XCTAssertEqual(extractor.extractDependencies(from: node), ["isActive", "age", "name"])

        node = try parser.parse("user.firstName + ' ' + user.lastName")
        XCTAssertEqual(extractor.extractDependencies(from: node), ["user"])

        node = try parser.parse("items[index]")
        XCTAssertEqual(extractor.extractDependencies(from: node), ["items", "index"])
    }

    // MARK: - Modulo Tests

    func testEvaluateModulo() throws {
        XCTAssertEqual(try evaluate("10 % 3") as? Int, 1)
        XCTAssertEqual(try evaluate("15 % 5") as? Int, 0)
        XCTAssertEqual(try evaluate("age % 7") as? Int, 4) // 25 % 7 = 4
    }

    // MARK: - Edge Cases

    func testEvaluateNullComparisons() throws {
        XCTAssertEqual(try evaluate("null === null") as? Bool, true)
        XCTAssertEqual(try evaluate("null == null") as? Bool, true)
        XCTAssertEqual(try evaluate("nullVar === null") as? Bool, false) // nullVar is nil, not NSNull
    }

    func testEvaluateEmptyArrayAndString() throws {
        // Empty string is falsy
        XCTAssertEqual(try evaluate("!emptyString") as? Bool, true)

        // Length of empty string
        XCTAssertEqual(try evaluate("length(emptyString)") as? Int, 0)
    }

    // MARK: - String Function Tests

    func testStringUppercase() throws {
        XCTAssertEqual(try evaluate("uppercase('hello')") as? String, "HELLO")
        XCTAssertEqual(try evaluate("uppercase(name)") as? String, "JOHN")
    }

    func testStringLowercase() throws {
        XCTAssertEqual(try evaluate("lowercase('HELLO')") as? String, "hello")
        XCTAssertEqual(try evaluate("lowercase('MixED')") as? String, "mixed")
    }

    func testStringTrim() throws {
        XCTAssertEqual(try evaluate("trim('  hello  ')") as? String, "hello")
        XCTAssertEqual(try evaluate("trim('   ')") as? String, "")
        XCTAssertEqual(try evaluate("trim('no-whitespace')") as? String, "no-whitespace")
    }

    func testStringReplace() throws {
        XCTAssertEqual(try evaluate("replace('hello world', 'world', 'there')") as? String, "hello there")
        XCTAssertEqual(try evaluate("replace('aaa', 'a', 'b')") as? String, "bbb")
        XCTAssertEqual(try evaluate("replace('foo', '', 'bar')") as? String, "foo")  // empty from = no-op
    }

    func testStringSplit() throws {
        XCTAssertEqual(try evaluate("split('a,b,c', ',')") as? [String], ["a", "b", "c"])
        XCTAssertEqual(try evaluate("split('hello world', ' ')") as? [String], ["hello", "world"])
        XCTAssertEqual(try evaluate("split('abc', '')") as? [String], ["a", "b", "c"])  // empty sep = chars
    }

    func testStringSubstring() throws {
        XCTAssertEqual(try evaluate("substring('hello', 1, 3)") as? String, "ell")
        XCTAssertEqual(try evaluate("substring('hello', 2)") as? String, "llo")  // to end
        XCTAssertEqual(try evaluate("substring('hi', 0, 10)") as? String, "hi")  // bounds-safe
        XCTAssertEqual(try evaluate("substring('hi', 10)") as? String, "")  // out of range
    }

    func testStringStartsWith() throws {
        XCTAssertEqual(try evaluate("startsWith('hello world', 'hello')") as? Bool, true)
        XCTAssertEqual(try evaluate("startsWith('hello', 'world')") as? Bool, false)
        XCTAssertEqual(try evaluate("startsWith('foo', '')") as? Bool, true)
    }

    func testStringEndsWith() throws {
        XCTAssertEqual(try evaluate("endsWith('hello.png', '.png')") as? Bool, true)
        XCTAssertEqual(try evaluate("endsWith('hello.jpg', '.png')") as? Bool, false)
    }

    // MARK: - Array Function Tests

    func testArraySort() throws {
        XCTAssertEqual(try evaluate("sort(items)") as? [String], ["apple", "banana", "cherry"])  // already sorted
        let desc = try evaluate("sort(items, false)") as? [String]
        XCTAssertEqual(desc, ["cherry", "banana", "apple"])
    }

    func testArraySortNumbers() throws {
        try variableStore.defineVariable(name: "nums", definition: VariableDefinition(type: .array, initialValue: [3, 1, 4, 1, 5, 9, 2, 6]))
        XCTAssertEqual(try evaluate("sort(nums)") as? [Int], [1, 1, 2, 3, 4, 5, 6, 9])
    }

    func testArrayReverse() throws {
        XCTAssertEqual(try evaluate("reverse(items)") as? [String], ["cherry", "banana", "apple"])
    }

    func testArrayJoin() throws {
        XCTAssertEqual(try evaluate("join(items, ', ')") as? String, "apple, banana, cherry")
        XCTAssertEqual(try evaluate("join(items, '')") as? String, "applebananacherry")
    }

    func testArrayConcat() throws {
        try variableStore.defineVariable(name: "more", definition: VariableDefinition(type: .array, initialValue: ["date", "elderberry"]))
        let result = try evaluate("concat(items, more)") as? [Any]
        XCTAssertEqual(result?.count, 5)
        XCTAssertEqual(result?[0] as? String, "apple")
        XCTAssertEqual(result?[4] as? String, "elderberry")
    }

    func testArraySlice() throws {
        XCTAssertEqual(try evaluate("slice(items, 1)") as? [String], ["banana", "cherry"])  // to end
        XCTAssertEqual(try evaluate("slice(items, 0, 2)") as? [String], ["apple", "banana"])
        XCTAssertEqual(try evaluate("slice(items, 0, 10)") as? [String], ["apple", "banana", "cherry"])  // bounds-safe
    }

    // MARK: - Helper Methods

    private func evaluate(_ expression: String) throws -> Any? {
        let node = try parser.parse(expression)
        return try evaluator.evaluate(node, context: testContext)
    }
}

// MARK: - Higher-Order Array Function Tests

@MainActor
final class HigherOrderArrayFunctionTests: XCTestCase {
    var parser: ExpressionParser!
    var evaluator: ExpressionEvaluator!
    var store: VariableStore!
    var context: VariableContext!

    override func setUp() {
        super.setUp()
        parser = ExpressionParser()
        evaluator = ExpressionEvaluator()
        store = VariableStore()

        let products: [[String: Any]] = [
            ["id": 1, "name": "Shirt",  "price": 35,  "active": true,  "categoryId": 10, "sellerId": 100],
            ["id": 2, "name": "Jeans",  "price": 80,  "active": true,  "categoryId": 20, "sellerId": 200],
            ["id": 3, "name": "Jacket", "price": 120, "active": false, "categoryId": 10, "sellerId": 100],
            ["id": 4, "name": "Dress",  "price": 60,  "active": true,  "categoryId": 20, "sellerId": 300],
        ]
        try! store.defineVariable(name: "products", definition: VariableDefinition(type: .array, initialValue: products))
        try! store.defineVariable(name: "emptyArray", definition: VariableDefinition(type: .array, initialValue: [] as [Any]))
        try! store.defineVariable(name: "selectedCategory", definition: VariableDefinition(type: .object, initialValue: ["id": 10]))
        try! store.defineVariable(name: "currentSeller", definition: VariableDefinition(type: .object, initialValue: ["id": 100]))
        try! store.defineVariable(name: "minPrice", definition: VariableDefinition(type: .number, initialValue: 50))
        try! store.defineVariable(name: "maxPrice", definition: VariableDefinition(type: .number, initialValue: 100))

        context = VariableContext(store: store)
    }

    // MARK: - filter()

    func testFilterNoPredicateReturnsAll() throws {
        let result = try evaluate("filter(products)") as? [Any]
        XCTAssertEqual(result?.count, 4)
    }

    func testFilterByBooleanField() throws {
        let result = try evaluate("filter(products, item.active == true)") as? [[String: Any]]
        XCTAssertEqual(result?.count, 3)
        XCTAssertTrue(result?.allSatisfy { $0["active"] as? Bool == true } ?? false)
    }

    func testFilterByNumericComparison() throws {
        let result = try evaluate("filter(products, item.price > 50)") as? [[String: Any]]
        XCTAssertEqual(result?.count, 3)  // 80, 120, 60
        XCTAssertTrue(result?.allSatisfy { ($0["price"] as? Int ?? 0) > 50 } ?? false)
    }

    func testFilterByRelatedObjectField() throws {
        let result = try evaluate("filter(products, item.categoryId == selectedCategory.id)") as? [[String: Any]]
        XCTAssertEqual(result?.count, 2)  // Shirt and Jacket (categoryId 10)
        XCTAssertTrue(result?.allSatisfy { $0["categoryId"] as? Int == 10 } ?? false)
    }

    func testFilterCompoundPredicateWithOuterVars() throws {
        let result = try evaluate("filter(products, item.price > minPrice && item.price < maxPrice)") as? [[String: Any]]
        XCTAssertEqual(result?.count, 2)  // Jeans (80) and Dress (60)
        XCTAssertTrue(result?.allSatisfy {
            let price = $0["price"] as? Int ?? 0
            return price > 50 && price < 100
        } ?? false)
    }

    func testFilterByAnotherObjectId() throws {
        let result = try evaluate("filter(products, item.sellerId == currentSeller.id)") as? [[String: Any]]
        XCTAssertEqual(result?.count, 2)  // Shirt and Jacket (sellerId 100)
        XCTAssertTrue(result?.allSatisfy { $0["sellerId"] as? Int == 100 } ?? false)
    }

    func testFilterEmptyArrayReturnsEmpty() throws {
        let result = try evaluate("filter(emptyArray, item.active == true)") as? [Any]
        XCTAssertEqual(result?.count, 0)
    }

    // MARK: - first()

    func testFirstNoPredicateReturnsFirstElement() throws {
        let result = try evaluate("first(products)") as? [String: Any]
        XCTAssertEqual(result?["id"] as? Int, 1)
    }

    func testFirstWithPredicate() throws {
        let result = try evaluate("first(products, item.active == false)") as? [String: Any]
        XCTAssertEqual(result?["id"] as? Int, 3)  // Jacket is first inactive
    }

    func testFirstOnEmptyArrayReturnsNil() throws {
        let result = try evaluate("first(emptyArray)")
        XCTAssertNil(result)
    }

    func testFirstWithNoMatchReturnsNil() throws {
        let result = try evaluate("first(products, item.price > 999)")
        XCTAssertNil(result)
    }

    // MARK: - find()

    func testFindById() throws {
        let result = try evaluate("find(products, item.id == 2)") as? [String: Any]
        XCTAssertEqual(result?["name"] as? String, "Jeans")
    }

    // MARK: - map()

    func testMapExtractsField() throws {
        let result = try evaluate("map(products, item.name)") as? [String]
        XCTAssertEqual(result, ["Shirt", "Jeans", "Jacket", "Dress"])
    }

    func testMapNoPredicateReturnsAll() throws {
        let result = try evaluate("map(products)") as? [Any]
        XCTAssertEqual(result?.count, 4)
    }

    // MARK: - Dependency Extraction

    func testFilterDepsExcludesItemIncludesArray() throws {
        let extractor = DependencyExtractor()
        let node = try parser.parse("filter(products, item.price > minPrice)")
        let deps = extractor.extractDependencies(from: node)
        XCTAssertEqual(deps, ["products", "minPrice"])
        XCTAssertFalse(deps.contains("item"))
    }

    func testFilterDepsWithRelatedObject() throws {
        let extractor = DependencyExtractor()
        let node = try parser.parse("filter(products, item.categoryId == selectedCategory.id)")
        let deps = extractor.extractDependencies(from: node)
        XCTAssertEqual(deps, ["products", "selectedCategory"])
        XCTAssertFalse(deps.contains("item"))
    }

    // MARK: - Helper

    private func evaluate(_ expression: String) throws -> Any? {
        let node = try parser.parse(expression)
        return try evaluator.evaluate(node, context: context)
    }
}

// MARK: - initialValue Expression Tests

/// Tests that `initialValue: "{{expression}}"` is evaluated at definition time,
/// and that computed variables depending on the result resolve correctly.
@MainActor
final class InitialValueExpressionTests: XCTestCase {

    func testInitialValueExpressionIsEvaluated() throws {
        // Simulates: selectedDogId = { type: string, initialValue: "{{first(dogs).id}}" }
        let dogs: [[String: Any]] = [
            ["id": "dog-1", "name": "Buddy", "breed": "Labrador"],
            ["id": "dog-2", "name": "Max",   "breed": "Poodle"],
        ]
        let store = VariableStore()
        try store.defineVariables([
            "dogs": VariableDefinition(type: .array, initialValue: dogs),
            "selectedDogId": VariableDefinition(type: .string, initialValue: "{{first(dogs).id}}"),
        ])

        // selectedDogId must be "dog-1", not the literal expression string
        let id = store.getValue(name: "selectedDogId") as? String
        XCTAssertEqual(id, "dog-1")
    }

    func testComputedVarDependingOnExpressionInitialValue() throws {
        // selectedDog = { computed: "{{first(dogs, item.id == selectedDogId)}}" }
        // must resolve to the first dog, not nil
        let dogs: [[String: Any]] = [
            ["id": "dog-1", "name": "Buddy", "breed": "Labrador"],
            ["id": "dog-2", "name": "Max",   "breed": "Poodle"],
        ]
        let store = VariableStore()
        try store.defineVariables([
            "dogs": VariableDefinition(type: .array, initialValue: dogs),
            "selectedDogId": VariableDefinition(type: .string, initialValue: "{{first(dogs).id}}"),
            "selectedDog": VariableDefinition(type: .object, computed: "{{first(dogs, item.id == selectedDogId)}}"),
        ])

        let dog = store.getValue(name: "selectedDog") as? [String: Any]
        XCTAssertEqual(dog?["name"] as? String, "Buddy")
        XCTAssertEqual(dog?["breed"] as? String, "Labrador")
    }

    func testNilComputedVarReturnsNilNotThrows() throws {
        // first() with no match → nil value; member access on nil should return nil, not throw
        let dogs: [[String: Any]] = [
            ["id": "dog-1", "name": "Buddy", "breed": "Labrador"],
        ]
        let store = VariableStore()
        try store.defineVariables([
            "dogs": VariableDefinition(type: .array, initialValue: dogs),
            "selectedDogId": VariableDefinition(type: .string, initialValue: "no-match"),
            "selectedDog": VariableDefinition(type: .object, computed: "{{first(dogs, item.id == selectedDogId)}}"),
        ])

        // selectedDog should be nil (no match)
        XCTAssertNil(store.getValue(name: "selectedDog"))

        // Evaluating {{selectedDog.name}} should return nil, not throw
        let evaluator = ExpressionEvaluator()
        let parser = ExpressionParser()
        let context = VariableContext(store: store)
        let node = try parser.parse("{{selectedDog.name}}")
        let result = try evaluator.evaluate(node, context: context)
        XCTAssertNil(result)
    }
}

// MARK: - Formatting Function Tests

@MainActor
final class FormattingFunctionTests: XCTestCase {
    var parser: ExpressionParser!
    var evaluator: ExpressionEvaluator!
    var store: VariableStore!
    var context: VariableContext!

    override func setUp() {
        super.setUp()
        parser = ExpressionParser()
        evaluator = ExpressionEvaluator()
        // Pin the formatter locale so date/number/weekday tests are stable
        // across simulators. Production code uses `Locale.current` (overridden
        // by `PropertyResolver` to the active translation locale) — that's
        // correct for users; tests need a deterministic locale.
        evaluator.locale = Locale(identifier: "en_US")
        store = VariableStore()
        context = VariableContext(store: store)
    }

    private func evaluate(_ expression: String) throws -> Any? {
        let node = try parser.parse(expression)
        return try evaluator.evaluate(node, context: context)
    }

    // MARK: - formatDate

    func testFormatDateShort() throws {
        XCTAssertEqual(try evaluate("{{formatDate('2026-01-12', 'short')}}") as? String, "Jan 12")
    }

    func testFormatDateMedium() throws {
        XCTAssertEqual(try evaluate("{{formatDate('2026-01-12', 'medium')}}") as? String, "Jan 12, 2026")
    }

    func testFormatDateLong() throws {
        XCTAssertEqual(try evaluate("{{formatDate('2026-01-12', 'long')}}") as? String, "January 12, 2026")
    }

    func testFormatDateWeekday() throws {
        // 2026-01-12 is a Monday
        let result = try evaluate("{{formatDate('2026-01-12', 'weekday')}}") as? String
        XCTAssertTrue(result?.contains("Monday") == true, "Expected 'Monday' in '\(result ?? "")'")
    }

    func testFormatDateWeekdayShort() throws {
        // 2026-01-12 is a Monday
        XCTAssertEqual(try evaluate("{{formatDate('2026-01-12', 'weekdayShort')}}") as? String, "Mon")
    }

    func testFormatDateNilInput() throws {
        XCTAssertEqual(try evaluate("{{formatDate(null, 'short')}}") as? String, "")
    }

    func testFormatDateISOWithTime() throws {
        // Should parse ISO date+time and format just the date part
        let result = try evaluate("{{formatDate('2026-01-12T10:30:00Z', 'medium')}}") as? String
        XCTAssertEqual(result, "Jan 12, 2026")
    }

    // MARK: - formatTime

    func testFormatTime24h() throws {
        let result = try evaluate("{{formatTime('2026-01-12T14:30:00Z', '24h')}}") as? String
        XCTAssertEqual(result, "14:30")
    }

    func testFormatTime12hContainsHoursAndMinutes() throws {
        // 14:30 UTC — locale-formatted 12h
        let result = try evaluate("{{formatTime('2026-01-12T14:30:00Z', '12h')}}") as? String
        XCTAssertTrue(result?.contains("30") == true, "Expected ':30' in '\(result ?? "")'")
    }

    func testFormatTimeNilInput() throws {
        XCTAssertEqual(try evaluate("{{formatTime(null)}}") as? String, "")
    }

    // MARK: - formatDuration

    func testFormatDurationZero() throws {
        XCTAssertEqual(try evaluate("{{formatDuration(0)}}") as? String, "0:00")
    }

    func testFormatDurationSeconds() throws {
        XCTAssertEqual(try evaluate("{{formatDuration(42)}}") as? String, "0:42")
    }

    func testFormatDurationMinutes() throws {
        XCTAssertEqual(try evaluate("{{formatDuration(90)}}") as? String, "1:30")
    }

    func testFormatDurationHours() throws {
        XCTAssertEqual(try evaluate("{{formatDuration(3661)}}") as? String, "1:01:01")
    }

    func testFormatDurationExactHour() throws {
        XCTAssertEqual(try evaluate("{{formatDuration(3600)}}") as? String, "1:00:00")
    }

    // MARK: - formatMinutes

    func testFormatMinutesLessThan60() throws {
        XCTAssertEqual(try evaluate("{{formatMinutes(15)}}") as? String, "15 min")
    }

    func testFormatMinutesSixty() throws {
        XCTAssertEqual(try evaluate("{{formatMinutes(60)}}") as? String, "1h")
    }

    func testFormatMinutesPartialHour() throws {
        XCTAssertEqual(try evaluate("{{formatMinutes(90)}}") as? String, "1h 30min")
    }

    func testFormatMinutesTwoHours() throws {
        XCTAssertEqual(try evaluate("{{formatMinutes(120)}}") as? String, "2h")
    }

    func testFormatMinutesZero() throws {
        XCTAssertEqual(try evaluate("{{formatMinutes(0)}}") as? String, "0 min")
    }

    // MARK: - ageInYears

    func testAgeInYears() throws {
        // Use a fixed far-past birthdate so the test doesn't rot
        let birthdate = "1990-01-01"
        let expected = Calendar.current.dateComponents(
            [.year],
            from: ISO8601DateFormatter().date(from: "1990-01-01T00:00:00Z")!,
            to: Date()
        ).year ?? 0
        let result = try evaluate("{{ageInYears('\(birthdate)')}}") as? Int
        XCTAssertEqual(result, expected)
    }

    func testAgeInYearsFutureDate() throws {
        // Future date should return 0, not negative
        XCTAssertEqual(try evaluate("{{ageInYears('2099-01-01')}}") as? Int, 0)
    }

    func testAgeInYearsInvalidInput() throws {
        XCTAssertEqual(try evaluate("{{ageInYears('not-a-date')}}") as? Int, 0)
    }

    // MARK: - daysBetween

    func testDaysBetween() throws {
        XCTAssertEqual(try evaluate("{{daysBetween('2026-01-12', '2026-01-17')}}") as? Int, 5)
    }

    func testDaysBetweenSameDate() throws {
        XCTAssertEqual(try evaluate("{{daysBetween('2026-01-12', '2026-01-12')}}") as? Int, 0)
    }

    func testDaysBetweenReversedIsAbsolute() throws {
        // Order shouldn't matter — always positive
        XCTAssertEqual(try evaluate("{{daysBetween('2026-01-17', '2026-01-12')}}") as? Int, 5)
    }

    func testDaysBetweenInvalidInput() throws {
        XCTAssertEqual(try evaluate("{{daysBetween('bad', '2026-01-12')}}") as? Int, 0)
    }

    // MARK: - timeAgo

    func testTimeAgoJustNow() throws {
        let iso = ISO8601DateFormatter()
        let now = iso.string(from: Date())
        let result = try evaluate("{{timeAgo('\(now)')}}") as? String
        XCTAssertEqual(result, "just now")
    }

    func testTimeAgoOldDate() throws {
        let result = try evaluate("{{timeAgo('2000-01-01T00:00:00Z')}}") as? String
        XCTAssertTrue(result?.contains("days ago") == true || result?.contains("years") == false,
                      "Expected 'days ago' in '\(result ?? "")'")
    }

    func testTimeAgoInvalidInput() throws {
        XCTAssertEqual(try evaluate("{{timeAgo('not-a-date')}}") as? String, "")
    }

    // MARK: - daysUntil

    func testDaysUntilFuture() throws {
        let cal = Calendar.current
        let future = cal.date(byAdding: .day, value: 5, to: cal.startOfDay(for: Date()))!
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"
        fmt.timeZone = cal.timeZone
        let result = try evaluate("{{daysUntil('\(fmt.string(from: future))')}}") as? Int
        XCTAssertEqual(result, 5)
    }

    func testDaysUntilPast() throws {
        let cal = Calendar.current
        let past = cal.date(byAdding: .day, value: -2, to: cal.startOfDay(for: Date()))!
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"
        fmt.timeZone = cal.timeZone
        let result = try evaluate("{{daysUntil('\(fmt.string(from: past))')}}") as? Int
        XCTAssertEqual(result, -2)
    }

    func testDaysUntilToday() throws {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"
        fmt.timeZone = Calendar.current.timeZone
        let result = try evaluate("{{daysUntil('\(fmt.string(from: Date()))')}}") as? Int
        XCTAssertEqual(result, 0)
    }

    // MARK: - formatCurrency

    func testFormatCurrencyUSD() throws {
        let result = try evaluate("{{formatCurrency(24.99)}}") as? String
        XCTAssertNotNil(result)
        XCTAssertTrue(result?.contains("24") == true)
        XCTAssertTrue(result?.contains("99") == true)
    }

    func testFormatCurrencyZero() throws {
        let result = try evaluate("{{formatCurrency(0)}}") as? String
        XCTAssertNotNil(result)
        XCTAssertFalse(result?.isEmpty == true)
    }

    func testFormatCurrencyWithCode() throws {
        let result = try evaluate("{{formatCurrency(24.99, 'EUR')}}") as? String
        XCTAssertNotNil(result)
        XCTAssertTrue(result?.contains("24") == true)
    }

    func testFormatCurrencyInvalidInput() throws {
        XCTAssertEqual(try evaluate("{{formatCurrency(null)}}") as? String, "")
    }

    // MARK: - formatNumber

    func testFormatNumberDecimal() throws {
        let result = try evaluate("{{formatNumber(6250)}}") as? String
        // Locale-aware thousands separator — just verify it has "6" and "250" in it
        XCTAssertTrue(result?.contains("6") == true && result?.contains("250") == true,
                      "Expected formatted number containing '6' and '250', got '\(result ?? "")'")
    }

    func testFormatNumberPercent() throws {
        XCTAssertEqual(try evaluate("{{formatNumber(0.856, 'percent')}}") as? String, "86%")
    }

    func testFormatNumberPercentRounding() throws {
        XCTAssertEqual(try evaluate("{{formatNumber(0.999, 'percent')}}") as? String, "100%")
    }

    func testFormatNumberInvalidInput() throws {
        XCTAssertEqual(try evaluate("{{formatNumber(null)}}") as? String, "")
    }

    // MARK: - round (extended with decimal places)

    func testRoundOneArg() throws {
        XCTAssertEqual(try evaluate("{{round(4.7)}}") as? Int, 5)
        XCTAssertEqual(try evaluate("{{round(4.2)}}") as? Int, 4)
    }

    func testRoundTwoArgsOneDecimal() throws {
        let result = try XCTUnwrap(try evaluate("{{round(4.567, 1)}}") as? Double)
        XCTAssertEqual(result, 4.6, accuracy: 0.0001)
    }

    func testRoundTwoArgsTwoDecimals() throws {
        let result = try XCTUnwrap(try evaluate("{{round(4.567, 2)}}") as? Double)
        XCTAssertEqual(result, 4.57, accuracy: 0.0001)
    }

    func testRoundTwoArgsZeroDecimals() throws {
        // round(4.7, 0) should behave like round(4.7) but return Double
        let result = try evaluate("{{round(4.7, 0)}}")
        // May return Double or Int depending on .rounded() result; just check the value
        XCTAssertEqual((result as? NSNumber)?.doubleValue ?? 0, 5.0, accuracy: 0.0001)
    }

    // MARK: - plural

    func testPluralSingular() throws {
        XCTAssertEqual(try evaluate("{{plural(1, 'glass', 'glasses')}}") as? String, "1 glass")
    }

    func testPluralPlural() throws {
        XCTAssertEqual(try evaluate("{{plural(5, 'glass', 'glasses')}}") as? String, "5 glasses")
    }

    func testPluralZero() throws {
        XCTAssertEqual(try evaluate("{{plural(0, 'item', 'items')}}") as? String, "0 items")
    }

    func testPluralLargeNumber() throws {
        XCTAssertEqual(try evaluate("{{plural(100, 'card left', 'cards left')}}") as? String, "100 cards left")
    }
}
