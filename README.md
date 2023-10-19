# Metabase connector for Power Query

This custom connector allows Power Query display and query Metabase tables and questions (queries saved in metabase).

## Motivation

Metabase is an Open-Source data visualization solution and has a very good access management and data discovery / exploration features. This connector allows integration of Metabase databases and questions with Power BI to leverage its data visualization features.

## Future Improvements

### Authentication

Authentication is currently done in two ways:
- Username and Password
- Session Token (Recommended)

_*Session Token is recommended because as of now, this connector doesn't logout of the session and would generate a new session token every time._

### Data Retrieval

Currently every dataset is queried in its completion including for Preview, which might not be viable for large datasets.
It also does not support parameterized questions.
