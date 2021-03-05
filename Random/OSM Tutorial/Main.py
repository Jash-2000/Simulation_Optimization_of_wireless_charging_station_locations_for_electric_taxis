from TOSMFile import TOSMFile

# Shortest Path Example
import networkx as nx
import random # random determination of a source node (only for the example)

if __name__ == "__main__":

    InputFolder  = './Input/'
    OutputFolder = './Output/'
    #FileName = "KaiserslauternNutzbareStrassenSplit.osm"
    FileName = "CBD_Streets.osm"

    
    MyOSMFile = TOSMFile(FileName,InputFolder)
    
    ParseSettings = {}
    #ParseSettings['AllowedWays'] = ['motorway','trunk','primary','secondary','tertiary','unclassified','residential','service','motorway_link','trunk_link','primary_link','secondary_link','tertiary_link','living_street']:
    ParseSettings['AllowedWays'] = ['motorway','trunk','primary','motorway_link','trunk_link','primary_link']
    
    # Read Input
    print 'Parse OSM File:',
    MyOSMFile.ParseOSMFile(ParseSettings)
    print 'OK'
    
    #print 'Test OSM File on consistency:',
    #MyOSMFile.TestOSMFile()
    #print 'OK'
    
    print 'RemoveMiddleCrossings (can take some time):',
    MyOSMFile.RemoveMiddleCrossings()
    print 'OK\n   -> Maybe new ways are build with NEW ID'
    
    # Compute Path Lengths
    print 'Parse Orig. Path Way Length:',
    MyOSMFile.ComputeWayLengths()
    print 'OK'


    #print 'Export Initial Graph:',
    #MyOSMFile.ExportCurrentOSMFile(FileName+"_Initial.osm",OutputFolder,Linearized=False)
    #print 'OK'    
    
    print 'Export Linearized Graph:',
    MyOSMFile.ExportCurrentOSMFile(FileName+"_Linear.osm",OutputFolder,Linearized=True)
    print 'OK'        
    
    
    
    
    # Get linearized Graph
    print 'Get linearized graph:',
    G = MyOSMFile.GetGraph(Format='Networkx',Linear=True)
    print 'OK'
    
    
    ##########
    print 'Shortest Path Example:'
    
    # Choose a random soruce s
    s = random.choice(G.nodes())
    Distance  = nx.shortest_path_length(G,source=s)
    print 'Distance from source',s,':',
    print Distance
        
               
    print "* * * * * * Finished * * * * * *"