ComfyUI + Ollama — Debugging Handoff Brief
Purpose: Document debugging findings and working changes from the session. Use this brief as input for a controlled refactor or fork of the ComfyUI-LLMNodes library.
Status: The existing image-generation workflow, Ollama text-generation node, and Ollama server node were all working at the end of the session.
1. Executive summary
We established a working text-generation path in ComfyUI using an Ollama model hosted on an M5 MacBook, accessed from an Oryx Linux machine through a local tunnel.
The main runtime bug was an incorrect boolean condition around an optional image input. When the image was None, the code still entered the image-processing branch and attempted to convert the nonexistent image. Changing or to and fixed the observed failure.
The model input in OllamaGenerateNode was also changed from a dynamic dropdown to a string input, allowing the remote model name to be entered directly.
We then experimented with prompt engineering. The initial generated image contained two fused foxes and missing legs. After adding instructions emphasizing a single subject and anatomically coherent limbs, a subsequent image showed one fox with a coherent body, four visible legs, and believable proportions, according to the user's assessment.
Primary engineering principle: preserve working behavior, test small changes, and avoid broad refactoring before inspecting the current codebase.
2. Environment and reproduction context
Item	Observed value
ComfyUI URL	http://127.0.0.1:8188
Custom node file	/home/vansweej/Work/comfyui/data/custom_nodes/llmnodes/ollama_nodes.py
Custom node pack	ComfyUI-LLMNodes
Remote Ollama endpoint from Oryx	http://127.0.0.1:11435
Oryx-local Ollama	Port 11434; reported to contain embedding models only
Model tested	qwen3.5:4b
Text node	OllamaGenerateNode
Text preview	PreviewAny
The remote endpoint is accessed through a tunnel from Oryx to the M5 MacBook. Do not assume ports 11434 and 11435 refer to the same Ollama instance.
A direct API test succeeded:
curl -s http://127.0.0.1:11435/api/generate \
  -d '{"model":"qwen3.5:4b","prompt":"Reply with exactly: test successful","stream":false}'


The response included the expected text, test successful, as well as a separate, large thinking field. This confirmed basic connectivity and model availability through that endpoint.
3. Confirmed bug: optional image handling
Symptom
Running OllamaGenerateNode without an image produced:
TypeError: 'NoneType' object is not subscriptable


The traceback pointed to this call chain:
- OllamaGenerateNode.run, around line 254
- ollama_generate, around line 125
- image_tensor_to_base64(image), around line 24
The failing operation was:
img = image_tensor[0].cpu().numpy()



Root cause
The relevant condition in ollama_generate was:
if image is not None or image != "":



When image is None, the first comparison is false, but None != "" is true. Because the condition uses or, the image-processing branch executes even though there is no image.
Patch applied
The condition was changed to:
if image is not None and image != "":



After the change, text generation succeeded. The existing image-generation workflow continued to work.
Recommended hardening
The minimal patch fixes the observed None case. However, the code should be made explicitly type-safe because image may be a tensor or a string.
A possible clearer implementation is:
has_image = image is not None and not (    isinstance(image, str) and image == "")if has_image:    if isinstance(image, str):        image_b64 = image_path_to_base64(image)    else:        image_b64 = image_tensor_to_base64(image)    user_message["images"] = [image_b64]



Inspect the supported input types and existing conventions before adopting this exact implementation.
Required regression tests
- image=None: skip image conversion and allow text-only generation.
- image="": skip image conversion if empty string means no image.
- Valid path string: use path-based conversion.
- Valid image tensor: use tensor-based conversion.
- Invalid path or malformed tensor: raise a clear, actionable error.
4. Model input adjustment
The user modified OllamaGenerateNode.INPUT_TYPES() so that the model input is a string with default qwen3.5:4b, rather than a dynamic dropdown.
This allowed the model name to be entered directly and was reflected in the workflow JSON.
This was a UI/configuration adaptation, not a confirmed runtime bug.
Refactor opportunity
Support arbitrary model names without requiring a hard-coded dropdown list. Optional model discovery or validation may still be useful, but it should not make node loading unnecessarily dependent on a successful network request.
If a requested model is unavailable, return a useful error message.
5. Server and endpoint configuration
The Ollama server node was configured for port 11435 and confirmed working.
In the workflow inspected during the session, OllamaGenerateNode had its server_url set directly to:
http://127.0.0.1:11435


The server node was not connected to the text-generation node.
Therefore, the following were verified independently:
- The Ollama server node works.
- The text-generation node can use the remote Ollama endpoint.
- Text generation succeeds through the tunnel.
Not verified: passing the endpoint from the server node into the text-generation node through a graph connection.
Refactor opportunity
Make endpoint configuration explicit and consistent.
If the server node is intended to provide the endpoint, verify that connecting it actually controls the generation node's endpoint. Otherwise, document that each generation node owns its URL.
Avoid competing sources of configuration or unclear precedence between node-level fields and server-node outputs.
6. Text-generation implementation
The observed function signature was:
def ollama_generate(    model: str,    user_prompt: str,    system_prompt: str,    num_ctx: int,    image=None,    seed=None,    temperature: float = 0.7,    host: str = "http://127.0.0.1:11434",) -> str:



The function:
1. Builds a URL ending in /api/chat.
2. Creates system and user messages.
3. Adds optional num_ctx, seed, and temperature settings.
4. Sends a non-streaming request with a 300-second timeout.
5. Calls raise_for_status().
6. Parses the JSON response.
7. Returns data["message"]["content"].
The full source file and all call sites were not audited during this session. Inspect the actual repository before refactoring.
Recommended robustness checks
Test and handle:
- Unreachable host or connection refused.
- Request timeout.
- HTTP error responses.
- Unavailable model.
- Malformed JSON.
- Missing message or content fields.
- Empty model response.
- Differences between /api/chat and /api/generate.
- Unexpected metadata or reasoning fields that might leak into user-facing prompt output.
Do not assume the response format of one endpoint applies to the other.
7. Prompt-generation experiment
The text node was configured to turn a short idea into a detailed image-generation prompt.
The test input was:
A fox in a snowy forest at night


The first generated prompt included a red fox, snow-covered pine trees, blue moonlight, amber eyes, low-angle composition, atmospheric mist, bokeh, and hyper-realistic photography details.
The first image showed two foxes fused together and missing legs.
The system prompt was then augmented with instructions to:
- Specify the exact number of main subjects.
- Describe a single animal with a coherent body.
- Specify anatomically plausible limbs.
- Use a simple, physically plausible pose.
- Keep limbs naturally connected and visually distinct.
- Avoid fused body parts, duplicate subjects, and ambiguous overlaps.
- Prioritize a clear silhouette over excessive decorative detail.
A subsequent image was assessed by the user as showing a single fox, a coherent body, four visible legs, and believable proportions.
Interpretation
This is promising qualitative evidence that prompt constraints may help, but it is not a controlled experiment. The change cannot be proven to be the sole cause of the improvement, and prompt wording cannot guarantee correct anatomy.
Keep prompt templates editable and separate from API transport code. Do not hard-code fox-specific instructions into generic generation logic.
8. Workflow state at session end
The following values were observed:
- Model: qwen3.5:4b
- Text node server URL: http://127.0.0.1:11435
- Temperature: 0.7
- Max tokens shown in workflow: 4096
- Text output connected to PreviewAny
- Ollama server node working
- Existing OllamaImageGen node working
Critical guardrail: the existing OllamaImageGen path is the known-good image-generation baseline. Do not modify it casually. Only change it if inspection and regression tests demonstrate a necessary fix.
9. Recommended refactor plan
P0 — Preserve baseline and add tests
1. Inspect the current repository and working-tree diff.
2. Create a branch or fork before broad changes.
3. Add regression tests for optional image values.
4. Verify the existing image-generation workflow remains functional.
5. Verify remote text generation through the tunnel.
P0 — Clarify endpoint configuration
1. Identify the intended source of the server URL.
2. Test connected server-node behavior if supported.
3. Define precedence between node-level URLs and server-node outputs.
4. Make the configured endpoint visible and diagnosable.
P1 — Improve API error handling
1. Convert connection, timeout, HTTP, JSON, and response-shape failures into actionable errors.
2. Validate response fields before indexing them.
3. Keep /api/chat and /api/generate handling distinct.
4. Ensure only intended prompt text reaches downstream nodes.
P1 — Improve configuration UX
1. Allow arbitrary model names.
2. Document defaults and endpoint precedence.
3. Report unavailable models clearly.
4. Avoid unnecessary network calls during node loading or UI refresh.
P2 — Improve the prompt pipeline
1. Keep system prompts and templates editable.
2. Consider separate nodes for generation, critique/refinement, and positive/negative prompt splitting.
3. Evaluate prompts using explicit criteria: subject fidelity, anatomy, composition, lighting, style, and unnecessary detail.
4. Save representative inputs and outputs for repeatable comparisons.
10. Acceptance criteria
- Text-only generation succeeds when the image input is omitted or None.
- Empty image input behaves as documented.
- Valid path and tensor image inputs continue to work.
- The existing OllamaImageGen workflow remains functional.
- Remote text generation works through the configured tunnel.
- Endpoint configuration has a clear, tested source of truth.
- Network, HTTP, model, and response errors are actionable.
- The text node returns only the intended prompt content.
- Regression tests cover optional image handling and major endpoint/error paths.
11. Instructions for the coding harness
Start by inspecting the actual repository, current diff, node definitions, helper functions, and call sites. This brief records session observations and is not a substitute for source inspection.
Before broad changes:
1. Report the relevant code paths and existing tests.
2. Propose a small patch plan with regression tests.
3. Make minimal changes and run the tests.
4. Report changed files, tests run, and any behavior that remains unverified.
Do not rewrite the library wholesale without approval.
Scope guardrails
- Preserve the working OllamaImageGen path.
- Keep prompt-template experiments separate from Python transport/API fixes.
- Do not silently change endpoint defaults or precedence.
- Do not remove image support while fixing text-only behavior.
- Do not assume ports 11434 and 11435 point to the same Ollama instance.
- Clearly distinguish confirmed findings from assumptions and recommendations.
Final status
Confirmed working: baseline image generation, remote Ollama text generation, and the Ollama server node.
Confirmed source patch: changed the optional-image condition from or to and to prevent None from entering image conversion.
Confirmed UI adjustment: changed the model field to a string input so qwen3.5:4b could be entered directly.
Prompt experiment: revised subject-integrity instructions correlated with a more anatomically coherent fox image in the user's assessment.
Next step: use the coding harness to inspect the repository and carry out a controlled refactor or fork, beginning with regression tests and endpoint clarity.