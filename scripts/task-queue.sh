#!/bin/bash
QUEUE_DIR=".task-queue"
mkdir -p "$QUEUE_DIR"/{pending,active,done}

case "${1:-}" in
    add)
        ID=$(date +%s%N | cut -c1-13)
        echo "$2" > "$QUEUE_DIR/pending/$ID.md"
        echo "Task $ID queued"
        ;;
    next)
        # Atomic claim: attempt mv directly; if it fails, another agent got it first
        CLAIMED=false
        for NEXT in "$QUEUE_DIR/pending/"*; do
            [ -e "$NEXT" ] || continue
            FILENAME=$(basename "$NEXT")
            if mv "$QUEUE_DIR/pending/$FILENAME" "$QUEUE_DIR/active/$FILENAME" 2>/dev/null; then
                cat "$QUEUE_DIR/active/$FILENAME"
                CLAIMED=true
                break
            fi
        done
        [ "$CLAIMED" = false ] && echo "Empty" && exit 0
        ;;
    done)
        mv "$QUEUE_DIR/active/${2}.md" "$QUEUE_DIR/done/${2}.md" 2>/dev/null
        ;;
    list)
        echo "Pending:" && ls "$QUEUE_DIR/pending/" 2>/dev/null
        echo "Active:"  && ls "$QUEUE_DIR/active/"  2>/dev/null
        echo "Done:"    && ls "$QUEUE_DIR/done/"    2>/dev/null
        ;;
    *)  echo "Usage: task-queue.sh {add|next|done|list} [args]" ;;
esac
