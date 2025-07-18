#include "nix/main/loggers.hh"
#include "nix/util/environment-variables.hh"
#include "nix/main/progress-bar.hh"

namespace nix {

LogFormat defaultLogFormat = LogFormat::raw;

LogFormat parseLogFormat(const std::string & logFormatStr)
{
    if (logFormatStr == "raw" || getEnv("NIX_GET_COMPLETIONS"))
        return LogFormat::raw;
    else if (logFormatStr == "raw-with-logs")
        return LogFormat::rawWithLogs;
    else if (logFormatStr == "internal-json")
        return LogFormat::internalJSON;
    else if (logFormatStr == "bar")
        return LogFormat::bar;
    else if (logFormatStr == "bar-with-logs")
        return LogFormat::barWithLogs;
    throw Error("option 'log-format' has an invalid value '%s'", logFormatStr);
}

std::unique_ptr<Logger> makeDefaultLogger()
{
    switch (defaultLogFormat) {
    case LogFormat::raw:
        return makeSimpleLogger(false);
    case LogFormat::rawWithLogs:
        return makeSimpleLogger(true);
    case LogFormat::internalJSON:
        return makeJSONLogger(getStandardError());
    case LogFormat::bar:
        return makeProgressBar();
    case LogFormat::barWithLogs: {
        auto logger = makeProgressBar();
        logger->setPrintBuildLogs(true);
        return logger;
    }
    default:
        unreachable();
    }
}

void setLogFormat(const std::string & logFormatStr)
{
    setLogFormat(parseLogFormat(logFormatStr));
}

void setLogFormat(const LogFormat & logFormat)
{
    defaultLogFormat = logFormat;
    logger = makeDefaultLogger();
}

} // namespace nix
