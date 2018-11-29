using LmpGlobal;
using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Net;

namespace LmpCommon
{
    /// <summary>
    /// This class retrieves the ips of master servers that are stored in:
    /// <see cref="RepoConstants.MasterServersListUrl"/>
    /// </summary>
    public static class MasterServerRetriever
    {
        /// <summary>
        /// Download the master server list from the MasterServersListUrl and return the ones that are correctly written
        /// We should add a ping check aswell...
        /// </summary>
        /// <returns></returns>
        public static string[] RetrieveWorkingMasterServersEndpoints()
        {
            try
            {
                ServicePointManager.ServerCertificateValidationCallback = GithubCertification.MyRemoteCertificateValidationCallback;
                var parsedServers = new List<IPEndPoint>();
                using (var client = new WebClient())
                using (var stream = client.OpenRead(RepoConstants.MasterServersListUrl))
                {
                    using (var reader = new StreamReader(stream))
                    {
                        var content = reader.ReadToEnd();
                        var servers = content
                            .Trim()
                            .Split('\n')
                            .Where(s => !s.StartsWith("#") && s.Contains(":") && !string.IsNullOrEmpty(s))
                            .ToArray();

                        foreach (var server in servers)
                        {
                            try
                            {
                                var ipPort = server.Split(':');
                                if (!IPAddress.TryParse(ipPort[0], out var ip))
                                {
                                    ip = Common.GetIpFromString(ipPort[0]);
                                }

                                if (ip != null && ushort.TryParse(ipPort[1], out var port))
                                {
                                    parsedServers.Add(new IPEndPoint(ip, port));
                                }
                            }
                            catch (Exception)
                            {
                                //Ignore the bad server   
                            }
                        }
                    }
                }

#if DEBUG
                parsedServers.Add(new IPEndPoint(IPAddress.Loopback, 8700));
#endif

                return parsedServers.Select(s => $"{s.Address.ToString()}:{s.Port}").ToArray();
            }
            catch (Exception)
            {
                return new string[0];
            }
        }
    }
}
