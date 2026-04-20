# Gemini Code Assist Instructions

## General Engineering Principles

- **Clean Code:** Strictly adhere to SOLID, DRY, and KISS principles. 
- **IOSP:** Strictly separate Integration (calling other functions) and Operation (doing the actual logic/computation). Do not mix them in the same function.
- **Simplicity (YAGNI):** Do not overengineer. Do not build abstract factories or generic interfaces unless explicitly asked. Implement only the requested feature.
- **Fail Fast:** Validate inputs early. Never swallow exceptions silently. Always handle or properly throw errors.
- **Naming & Comments:** Code must be self-documenting through expressive naming. Do not use abbreviations. Comment ONLY the "Why" (business logic, edge cases), never the "What".
- **Immutability:** Favor immutability. Never mutate function arguments. Return new objects or arrays instead of modifying existing ones, unless performance constraints explicitly demand it.
- **Security & Defensive Programming:** Never log sensitive information (PII, credentials, tokens). Always sanitize user inputs and treat external data as untrusted to prevent injection attacks.
- **Zero-Dependency Preference:** Prefer the standard library for solving problems. Do not introduce new external libraries or packages unless explicitly requested.

## Public API Documentation

All public functions and methods MUST include a formal documentation comment (e.g., JSDoc, Javadoc, Godoc). This comment must explicitly state:

  1. The purpose of the function.
  2. All inputs (parameters) and their meaning.
  3. The exact output (return value).
  4. Error handling: Explicitly list any Exceptions that might be thrown (in languages like Java, Python, TS/JS) OR explicitly document returned `error` values (specifically for Go).

## Refactoring & Testing

- **Boy Scout Rule:** When editing a file, gently refactor adjacent code if it violates these principles, without breaking the existing scope.
- **Meaningful Testing:** When generating unit tests, do not only test the "happy path". Explicitly write test cases for edge cases, boundary values, null/empty inputs, and expected errors/exceptions.

## Go (Golang) Specific Rules

- **Testing with Testify:** Always structure tests as Table-Driven Tests (`[]struct{ name string... }`).
  - Use `require` strictly for preconditions and error checks (e.g., `require.NoError(t, err)`) to halt the test immediately on failure and prevent nil-pointer panics.
  - Use `assert` strictly for value comparisons (e.g., `assert.Equal(t, expected, actual)`).
- **Idiomatic Error Handling:** Never panic in normal control flow or library code. Always wrap errors to preserve the chain using `fmt.Errorf("context: %w", err)` so `errors.Is` and `errors.As` continue to function.
- **Pointers vs. Values:** Default to passing structs by value to minimize heap allocations. Only use pointers (`*Struct`) if the function explicitly needs to mutate the struct, if the struct contains synchronization primitives (`sync.Mutex`), or if `nil` is a semantically meaningful state.
- **Concurrency Safety:** Never create a goroutine without knowing exactly how and when it will exit (prevent goroutine leaks). Always use `sync.WaitGroup`, Context cancellation, or channels to manage lifecycle. Prefer communicating state over channels rather than sharing memory with Mutexes.
- **Package Naming:** Never create packages named `util`, `common`, or `helpers`. Packages must be named after what they provide (e.g., `strings`, `database`, `auth`).

## Unity (C#) Specific Rules

- **Performance & GC Allocation:** Strictly avoid any memory allocations inside `Update()`, `FixedUpdate()`, and `LateUpdate()`. Cache objects (like `new WaitForSeconds()`) instead of creating them dynamically. Never use LINQ or heavy string concatenation in high-frequency loops to prevent Garbage Collection (GC) spikes.
- **Caching References:** Never call `GetComponent<T>()`, `GameObject.Find()`, `FindObjectOfType()`, or `Camera.main` inside update loops. Always query and cache these references exactly once in `Awake()` or `Start()`.
- **Encapsulation (Inspector):** Never use `public` fields solely to expose them in the Unity Inspector. Always use `[SerializeField] private Type variableName;`. If another script needs access, provide a `public` C# Property (`{ get; private set; }`).
- **Memory Leaks & Events:** Always explicitly unsubscribe from C# events (`+=` / `-=`) and delegates in `OnDisable()` or `OnDestroy()` to prevent memory leaks and ghost invocations when GameObjects are destroyed.
- **Instantiation vs. Pooling:** Avoid calling `Instantiate()` and `Destroy()` during active gameplay for frequent objects (like bullets or enemies). Use Object Pooling instead.
- **Coroutines & Async:** When writing Coroutines, ensure they yield properly and don't create infinite loops without `yield return null`. If using `async/await` (e.g., with UniTask), always pass a `CancellationToken` linked to the GameObject's lifecycle (`destroyCancellationToken`) to prevent exceptions when the object is destroyed before the task finishes.

## Kubernetes (k8s) Specific Rules

- **API Versions:** Strictly use current, stable Kubernetes API versions (e.g., `apps/v1` for Deployments and DaemonSets, `networking.k8s.io/v1` for Ingress). Never use deprecated versions like `extensions/v1beta1`.
- **Production Readiness:** Every Pod or Deployment MUST include `resources` (both `requests` and `limits` for CPU and Memory). Always include `livenessProbe` and `readinessProbe` definitions.
- **Security Context:** Default to secure configurations. Pods should include a `securityContext` setting `runAsNonRoot: true` and `allowPrivilegeEscalation: false` wherever technically feasible.
- **Labels & Selectors:** Always use standard Kubernetes labels (e.g., `app.kubernetes.io/name`, `app.kubernetes.io/component`) for consistency.

## Docker Specific Rules

- **Multi-Stage Builds:** Always use multi-stage builds (`AS builder`) for compiled languages or frontend frameworks to ensure the final image is as small as possible and does not contain build tools.
- **Layer Caching:** Optimize Dockerfile instructions for caching. Always copy dependency manifests (`package.json`, `go.mod`, `requirements.txt`) and install dependencies *before* copying the rest of the application source code.
- **Least Privilege:** Never run the final container as the `root` user. Always create a dedicated unprivileged user and use the `USER` directive before the `CMD` or `ENTRYPOINT`.
- **Base Images:** Default to lightweight base images like `alpine` or `-slim` variants unless `glibc` requirements dictate otherwise.

## Hugo (Static Site Generator) Specific Rules

- **Go Templating:** Write clean, idiomatic Hugo Go-Templates (`{{ }}`). Utilize built-in Hugo functions and template variables rather than reinventing logic (e.g., prefer `site.Params` over hardcoded values, use `relURL` or `absURL` for linking).
- **Asset Pipeline:** Strictly differentiate between the `/static` directory (for files copied exactly as-is, like favicons) and the `/assets` directory (for files processed via Hugo Pipes, like SCSS or JS minification).
- **Page Bundles:** Adhere strictly to Hugo's Page Bundle logic. Use `_index.md` for Branch Bundles (list pages/sections) and `index.md` for Leaf Bundles (single pages with local resources).
- **Shortcodes:** Do not invent non-existent shortcodes. Only use standard Hugo shortcodes (like `{{< figure >}}`) or explicitly request to create a custom shortcode in `layouts/shortcodes/` if needed.

## TypeScript & React Specific Rules

- **Functional Components & Hooks:** Write exclusively Functional Components. Never write Class Components. Use standard React Hooks (`useState`, `useRef`, `useContext`).
- **No Unnecessary Effects:** Do not use `useEffect` for derived state, data transformation, or filtering. Compute these values directly during render. Only use `useEffect` for true side effects (e.g., network requests, subscriptions, DOM manipulation).
- **Strict Interfaces:** Never use `any` or `prop-types`. Always define strict TypeScript `interface` or `type` blocks for Component props and state. Ensure all event handlers are properly typed.
- **Export Conventions:** Prefer named exports (`export const MyComponent`) over `default export`. This improves IDE refactoring, searchability, and tree-shaking.
- **State Management:** Keep local state as close to where it is used as possible. For complex local state, prefer `useReducer` over multiple `useState` hooks.

## Project Specific Rules