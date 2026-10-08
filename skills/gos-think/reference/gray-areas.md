# Gray Area Identification Method

## The Method

Don't use generic categories (UI/UX/Behavior/Performance). Generate
**domain-specific** gray areas based on the actual feature.

### Step 1: Read the requirement
### Step 2: Ask: "What decisions need to be made that the requirement doesn't specify?"
### Step 3: Generate domain-specific questions
### Step 4: Present to user for selection

## Examples by Domain

### Authentication feature →
- Session expiry policy? (24h? 7d? sliding?)
- Error message format? (structured JSON? plain text?)
- Multi-device handling? (allow concurrent? force logout?)
- Password requirements? (min length? complexity?)
- Token storage? (httpOnly cookie? localStorage?)

### CLI tool feature →
- Output format? (JSON? table? plain text? colored?)
- Flag naming? (--verbose vs -v? --output vs -o?)
- Progress reporting? (spinner? percentage? silent?)
- Error exit codes? (1 for all errors? semantic codes?)
- Config file? (YAML? TOML? JSON?)

### Data export feature →
- Export format? (CSV? JSON? XML?)
- Large dataset handling? (streaming? pagination? file download?)
- Field selection? (all fields? user picks? presets?)
- Date formatting? (ISO? locale-specific? relative?)

### API endpoint feature →
- Pagination style? (offset/limit? cursor? page?)
- Filtering? (query params? body? headers?)
- Versioning? (URL path? header? query param?)
- Rate limiting? (per user? per IP? global?)
- Error response shape? (RFC 7807? custom?)

## Presenting Gray Areas to Users

> "I've identified these gray areas:
> 1. Session expiry policy
> 2. Error message format
> 3. Token storage
>
> Which should we discuss? (pick all that apply)"

For each selected area, explore 2-3 options and let the user decide.
Each decision becomes a D-NN entry.
