# Metabase connector for Power Query

This custom connector allows Power Query display and query Metabase tables and questions (queries saved in metabase).

## Motivation

Metabase is an Open-Source data visualization solution and has a very good access management and data discovery / exploration features. This connector allows integration of Metabase databases and questions with Power BI to leverage its data visualization features.

## How to use it?
Copy the bin/AnyCPU/Debug/Metabase.mez file to Documents\Power BI Desktop\Custom Connectors.
On Power BI: Options -> Security -> Data Extensions -> Allow any extension to load without validation or warning.*

_*By doing this you will trust this connector, that's why it's open-source and you can verify and modify what it does._

## Limitations

### Authentication

Authentication is currently done in two ways:
- Username and Password
- Session Token (Recommended*)

_*Session Token is recommended because as of now, this connector doesn't logout of the session and would generate a new session token every time._

### Query Folding

Currently only row limit is applied. It was the main one, since it allows faster Preview.