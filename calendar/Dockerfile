# CalDAV-only MCP (iCloud calendars + to-dos) exposed as Streamable HTTP via supergateway
FROM node:22-alpine
RUN npm install -g caldav-mcp@0.10.0 supergateway@4.1.0 && npm cache clean --force
USER node
EXPOSE 3000
CMD ["supergateway", "--stdio", "caldav-mcp", "--outputTransport", "streamableHttp", "--port", "3000", "--healthEndpoint", "/healthz"]
