default:
    @just --list

# Autoformat the project tree
fmt:
    treefmt

# Run the project, recompiling as necessary
watch:
    watch-leptos-project

# Run leptops build
build *ARGS:
    cargo leptos build --release {{ARGS}}