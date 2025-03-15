SELF_PATH="$(realpath "${BASH_SOURCE[0]}")"
ZERO_PATH="$(realpath "$0")"
echo $SELF_PATH, $ZERO_PATH
if [[ "$SELF_PATH" == "$ZERO_PATH" ]]; then
    main $@