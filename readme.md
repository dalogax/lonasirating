# Lonas iRacing - lonasiracing.dalogax.com

This repository contains the Lonas iRacing site where team members can see their irating stats.

Irating stats are fetched from a 3rd party API located at https://iracing6-backend.herokuapp.com/api/member-career-stats/career/<iracing_id>
Example respones at example.json.

## Team members

- Luis - 918399
- Samu - 1096007
- Porta - 900904
- Marcos - 1094362
- Rubén - 1301050
- Dalogax - 305408

## Development

The app will be only client side, the API supports CORS so it can be called directly from the browser.

It will display irating statistics only for the classes sports_car and formula_car. Each class will be in one tab.

On each tab there will be a leaderboard with the current irating for each team member ordered by irating. Under it will be a chart with the last 12 months of irating data code colored by driver.

The design will be simple and mobile first with a header showing the team name.
