#!/bin/sh
#!/bin/sh

# Validate the number of arguments
if [ "$#" -ne 2 ]; then
    echo "Error: Two arguments are required."
    exit 1
fi

filesdir="$1"
searchstr="$2"

# Validate the directory
if [ ! -d "$filesdir" ]; then
    echo "Error: $filesdir is not a valid directory."
    exit 1
fi

# Count files recursively
numfiles=$(find "$filesdir" -type f | wc -l)

# Count matching lines recursively
matchinglines=$(grep -r -l -Z -F \
    "$searchstr" "$filesdir" 2>/dev/null \
    | tr -cd '\0' | wc -c)

# Replace the count above with matching line count
matchinglines=$(grep -r -F -h \
    "$searchstr" "$filesdir" | wc -l)

echo "The number of files are $numfiles and the number of matching lines are $matchinglines"

