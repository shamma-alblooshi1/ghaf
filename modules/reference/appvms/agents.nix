                                                                                                                                                                                             
# Copyright 2024 TII (SSRC) and the Ghaf contributors                                                                                                                                         
# SPDX-License-Identifier: Apache-2.0                                                                                                                                                         
#                                                                                                                                                                                             
{                                                                                                                                                                                             
  pkgs,                                                                                                                                                                                       
  lib,                                                                                                                                                                                        
  config,                                                                                                                                                                                     
  ...                                                                                                                                                                                         
}:                                                                                                                                                                                            
{                                                                                                                                                                                             
  multiagent = {                                                                                                                                                                              
    ramMb = 2048;                                                                                                                                                                             
    cores = 2;                                                                                                                                                                                
    borderColor = "#4A90E2";  # Blue color for AI/ML theme                                                                                                                                    
    ghafAudio.enable = false;  # Disable unless you need audio                                                                                                                                
    vtpm.enable = true;        # Enable for security                                                                                                                                          
    applications = [                                                                                                                                                                          
      {                                                                                                                                                                                       
        name = "Multi-Agent Framework";                                                                                                                                                       
        description = "AI Multi-Agent Framework with MCP Tools";                                                                                                                              
        packages = [pkgs.agents                                                                                                                                                                                                                                                                        
];                                                                                                                                                                                    
        icon = "applications-development";                                                                                                                                                    
        command = "multiagent-framework";                                                                                                                                                     
        extraModules = [                                                                                                                                                                      
          {                                                                                                                                                                                   
            # Add any specific configuration for your framework                                                                                                                               
            environment.systemPackages = [                                                                                                                                                                                                                                                                                                                          
            ];                                                                                                                                                                                
                                                                                                                                                                                              
            # Optional: Create a service                                                                                                                                                      
            systemd.user.services.multiagent-framework = {                                                                                                                                    
              description = "Multi-Agent Framework Service";                                                                                                                                  
              serviceConfig = {                                                                                                                                                               
                Type = "simple";                                                                                                                                                              
                Restart = "always";                                                                                                                                                           
                RestartSec = "10";                                                                                                                                                            
              };                                                                                                                                                                              
              enable = false;  # Set to true for auto-start                                                                                                                                   
            };                                                                                                                                                                                
          }                                                                                                                                                                                   
        ];                                                                                                                                                                                    
      }                                                                                                                                                                                       
    ];                                                                                                                                                                                        
    extraModules = [                                                                                                                                                                          
      {                                                                                                                                                                                       
        # Network access for your agents                                                                                                                                                      
        networking.enable = true;                                                                                                                                                             
                                                                                                                                                                                 
      }                                                                                                                                                                                       
    ];                                                                                                                                                                                        
  };                                                                                                                                                                                          
}