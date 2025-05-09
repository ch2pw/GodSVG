## Governance

Your contribution is always appreciated!

Contributions don't need to be perfect, but they must move GodSVG in the right direction. If you are planning to implement a feature or overhaul a system, it's important to write a proposal and discuss your ideas first. I will try to be quick with accepting or declining them. Please do understand that PRs with a large maintenance cost may be under high scrutiny because of their long-term responsibility, even in the absence of the original contributor.

## Setup

GodSVG is made in Godot using its GDScript language. Refer to the [README](https://github.com/MewPurPur/GodSVG?tab=readme-ov-file#how-to-get-it) on how to get GodSVG running.

Git must be configured, then you can clone the repository to your local machine: `git clone https://github.com/MewPurPur/GodSVG.git`

The documentation won't go into detail about how to use Git. Refer to outside resources if you are unfamiliar with it.

## PR workflow

Look through the list of issues to see if your contribution would resolve any of them. If said issue is not assigned to anyone and you don't want anyone else to work on it, ask to be assigned to the issue. If an issue doesn't exist and you want to fix a bug, then it's a good practice, but not required, to make an issue for it.

1. Fork the repository.
2. Create a new branch: `git checkout -b implement-gradients`
3. Make your modifications, add them with `git add .`
4. Commit your changes: `git commit -m "Implement the mask element"`
5. Push to the branch: `git push origin implement-masks`
6. Create a new pull request with a clear and informative title and describe your changes.

This is the preferred workflow, but tidiness is not as important as work being done, so feel free to do something different you may be comfortable with.

After submitting your pull request, I (MewPurPur) will review your changes and may provide feedback or request modifications. Be responsive to any comments or suggestions. Once your pull request is approved, it will be merged. Afterward, you can delete your branch from your fork.

## Translation

Editing translations is explained [here](translations/README.md)

## Code guidelines

To document some quirks of our code that we've decided on:

- StringNames are avoided when possible. We do this because it makes the codebase simpler, although if something is actually shown to be performance-critical, it can be reconsidered.
- Nodes may only be exported if their runtime structure isn't known.
- Strings are always translated with `Translator.translate()`, not `tr()`.

## Code style

For scripts, only GDScript code is allowed. Follow the [GDScript style guide](https://docs.godotengine.org/en/stable/tutorials/scripting/gdscript/gdscript_styleguide.html). Most of its rules are enforced here. Additionally:

- Static typing is used as much as possible.
- Comments are typically written like sentences with punctuation.
- Two spaces are used to separate inline comments and code.
- For empty lines in the middle of indented blocks, the scope's indentation is kept.
- Class names use `class_name X extends Y` syntax.

Don't make pull requests for code style changes without discussing them first (unless it's for corrections to abide by the ones described here). The same generally applies to making style changes unrelated to a PR's main goal. Pull requests may also get production tweaks to tweak their style before being merged.
