# codecs: Needed to save the osm file with the utf8 format
import codecs

# Copy entire elements
import copy

import networkx as nx

# SAX: Needed to parse the OSM File
import xml.sax as sax
import xml.sax

from GeneralFunctions import TDimensions

from TOSMNode import * 
from TOSMWay import *
from GeneralFunctions import stop,wait
from GeneralFunctions import FileExistCheck
from GeneralFunctions import Haversine_Distance
from arcpy.ddd import Idw

class TOSMFile(object):
    def __init__(self, FileName,  Folder):
        
        self.FileName = FileName
        self.Folder   = Folder
        
        # Test if the file is available
        FileExistCheck(Folder,FileName)
        
        # Dictionary with TNodes
        self.NodeList = {}
        
        # Dictionary with TWays
        self.WayList  = {}
        
    def ParseOSMFile(self,ParseSettings={}):   
        # Read File
        SourceFile = codecs.open(self.Folder+self.FileName,"r")

        # Main Parsing    
        sax.parse(SourceFile, ReadXMLWithSAXHandler(self.NodeList,self.WayList,ParseSettings))
    
    def ComputeWayLengths(self):
        for idWay in self.WayList:
            MyWay = self.WayList[idWay]

            MyWay.Length = 0
            for Index in range(0,len(MyWay.NodeList)-1): 
                NodeA = self.NodeList[MyWay.NodeList[Index]]
                NodeB = self.NodeList[MyWay.NodeList[Index+1]]    
                MyWay.Length += Haversine_Distance(NodeA.Lon, NodeA.Lat, NodeB.Lon, NodeB.Lat)
    
    def RemoveMiddleCrossings(self):
        
        # Count occuring of nodes
        for idNode in self.NodeList:
            self.NodeList[idNode].EndPosition    = 0
            self.NodeList[idNode].MiddlePosition = 0
            self.NodeList[idNode].ContainedInWay = {}
            
        for idWay in self.WayList:            
            MyWay = self.WayList[idWay]            

            self.NodeList[MyWay.NodeList[0]].EndPosition  += 1
            self.NodeList[MyWay.NodeList[-1]].EndPosition += 1
            for idNode in MyWay.NodeList[1:-1]:
                self.NodeList[idNode].MiddlePosition += 1
                
            for idNode in MyWay.NodeList:
                self.NodeList[idNode].ContainedInWay[idWay] = True                

#        Total = len(self.NodeList)
#        Counter = 0
#        for idNode in self.NodeList:
#            if (self.NodeList[idNode].MiddlePosition >= 1) & ((self.NodeList[idNode].EndPosition + self.NodeList[idNode].MiddlePosition) >= 2):
#                Counter +=1 

        for idNode in self.NodeList:
            if (self.NodeList[idNode].MiddlePosition >= 1) & ((self.NodeList[idNode].EndPosition + self.NodeList[idNode].MiddlePosition) >= 2):  
                
                #print self.NodeList[idNode].EndPosition,'',self.NodeList[idNode].MiddlePosition
                            
                self.SplitWaysOnGivenNodeID(idNode)
                  
    def SplitWaysOnGivenNodeID(self,idSplitNode):        
        NewWayID = self.GetFreeWayID()
        NewWays = []
        
        
        
        
        
        for idWay in self.NodeList[idSplitNode].ContainedInWay:
        #for idWay in self.WayList:
                     
            while idSplitNode in self.WayList[idWay].NodeList[1:-1]:
                
                
                #print 'Split Ways in node',idSplitNode,'in path',self.WayList[idWay].NodeList
                
                iPos = self.WayList[idWay].NodeList[1:-1].index(idSplitNode) + 1
                
                
                # Left Way is fine for this node
                LeftWay   = copy.deepcopy(self.WayList[idWay])
                LeftWay.idWay = NewWayID
                LeftWay.NodeList  = LeftWay.NodeList[:iPos+1]
                
                NewWays.append(LeftWay)
                
                RightWay  = self.WayList[idWay]
                
                #for idNode in RightWay.NodeList[:iPos]:
                    #del self.NodeList[idNode].ContainedInWay[idWay]                            
                                
                RightWay.NodeList = RightWay.NodeList[iPos:]
                
                
         

                self.NodeList[idSplitNode].EndPosition    += 2
                self.NodeList[idSplitNode].MiddlePosition -= 1   
                
                NewWayID = NewWayID + 1
                                
                
                
                #if idSplitNode == 1212940288:
                #    LeftWay.Print()
                #    RightWay.Print()
                #    stop('__________')
                
        for AddWay in NewWays:
            self.WayList[AddWay.idWay] = AddWay

            for idNode in AddWay.NodeList:
                self.NodeList[idNode].ContainedInWay[AddWay.idWay] = True              
        
    def Print(self):
        print 'Nodes:'
        for nodeID in self.NodeList:
            MyNode = self.NodeList[nodeID]
            MyNode.Print()   
        
        print '\nWays:'
        for wayID in self.WayList:
            MyWay = self.WayList[wayID]
            MyWay.Print()   
        
    def GetFreeWayID(self):
        MaxidWay = -float('inf')
        for idWay in self.WayList:
            MaxidWay = max(MaxidWay,idWay)
        return MaxidWay+1
      
    def GetGraph(self,Format='Networkx',Linear=True):
        
        if (Format != 'Networkx') | (Linear != True):
            stop('Currently only implemented for linearized Networkx graph')
        
        return self.GetLinearNetworkxGraph()
            
    def GetLinearNetworkxGraph(self):
        G = nx.MultiDiGraph()
    
        for idNode in self.NodeList:
            if self.NodeList[idNode].EndPosition > 0:
                G.add_node(idNode)
        
        for idWay in self.WayList:               
                
            MyWay = self.WayList[idWay]
                
            G.add_edge(MyWay.NodeList[0], MyWay.NodeList[-1], length=MyWay.Length)
                
            if MyWay.OneWay == False:
                G.add_edge(MyWay.NodeList[-1], MyWay.NodeList[0], length=MyWay.Length)
                
        return G        
         
    def ExportCurrentOSMFile(self,Filename="OSMExport.osm",Folder='./',Linearized=False):
        
        SaveOutputFileName = Folder + Filename
        f = open(SaveOutputFileName,"w")
        f.write("<?xml version='1.0' encoding='UTF-8'?>\n")
        #f.write("<osm version=\"0.6\" generator=\"Osmosis 0.43.1\">\n")
    
        MyDimensions = TDimensions()
        for nodeID in self.NodeList:
            MyDimensions.Add(self.NodeList[nodeID].Lon,self.NodeList[nodeID].Lat)

        f.write("<osm version=\"0.6\" generator=\"Osmosis 0.43.1\">\n")
        f.write('<bounds minlon="'+str(MyDimensions.xMin)+'" minlat="'+str(MyDimensions.yMin)+'" maxlon="'+str(MyDimensions.xMax)+'" maxlat="'+str(MyDimensions.yMax)+'" origin="osmconvert 0.7P"/> \n')
    
    
        for nodeID in self.NodeList:
            if (Linearized == False) | (self.NodeList[nodeID].EndPosition > 0):
                if (self.NodeList[nodeID].MiddlePosition + self.NodeList[nodeID].EndPosition) > 0:
                    f.write('<node id="'+str(nodeID)+'" lat="'+str(self.NodeList[nodeID].Lat)+'" lon="'+str(self.NodeList[nodeID].Lon)+'"/>\n')
                
    
        for wayID in self.WayList:
    
            f.write('<way id="'+str(wayID)+'" > \n')
            
            if Linearized:
                ConsideredNodes = [self.WayList[wayID].NodeList[0],self.WayList[wayID].NodeList[-1]]
            else:
                ConsideredNodes = self.WayList[wayID].NodeList
            
            for nodeID in ConsideredNodes:
                f.write('  <nd ref="'+str(nodeID)+'" />\n')
                f.write('  <tag k="highway" v="'+str(self.WayList[wayID].HighWayType)+'"/>\n')
                f.write('    <tag k="maxspeed" v="'+str(self.WayList[wayID].MaxSpeed)+'"/>\n')
                f.write('    <tag k="lanes" v="'+str(self.WayList[wayID].Lanes)+'"/>\n')

            if self.WayList[wayID].OneWay == True:
                f.write('    <tag k="oneway" v="yes"/>\n')
            f.write('</way>\n')
    
        f.write('</osm>\n')
    
        f.close()
     
    def TestOSMFile(self):
                 
        Error = False
                 
        # Test if each node of each way is defined
        for idWay in self.WayList:            
            MyWay = self.WayList[idWay]            
            
            for nodeID in MyWay.NodeList:
                
                if self.NodeList.has_key(nodeID) == False:
                    Error = True
                    print 'The node',nodeID,'is not defined in the node list'

        if Error:
            stop("ERROR STOP")
    
class ReadXMLWithSAXHandler(xml.sax.ContentHandler):
    def __init__(self,NodeList,WayList,Settings={}):
        xml.sax.ContentHandler.__init__(self)
 
        self.NodeList    = NodeList
        self.WayList     = WayList
        self.Settings    = Settings
 
        self.CurrentidWay= None
        
    def startElement(self, name, attrs):
        if name == "node":    
            idNode = int(attrs.getValue("id"))
            Lat    = float(attrs.getValue("lat"))
            Lon    = float(attrs.getValue("lon"))                
            self.NodeList[idNode] = TOSMNode(idNode,Lat,Lon)
        
        elif name == "way":            
            self.CurrentidWay = int(attrs.getValue("id"))            
            self.WayList[self.CurrentidWay] = TOSMWay(self.CurrentidWay)
        
        if self.CurrentidWay != None:
            if name == "nd":                
                self.WayList[self.CurrentidWay].AddNode(int(attrs.getValue("ref")))
            elif name == "tag":
                k = attrs.getValue("k")
               
                if k == "highway":
                    self.WayList[self.CurrentidWay].HighWayType = str(attrs.getValue("v"))
                elif k == "maxspeed": 
                    try:
                        self.WayList[self.CurrentidWay].MaxSpeed = float(attrs.getValue("v"))
                    except ValueError:
                        self.WayList[self.CurrentidWay].MaxSpeed = 130
                elif k == "oneway":                     
                    Help = attrs.getValue("v")
                    if Help == "yes":
                        self.WayList[self.CurrentidWay].OneWay = True
                    else:
                        self.WayList[self.CurrentidWay].OneWay = False
                elif k =="lanes":
                    try:
                        self.WayList[self.CurrentidWay].Lanes = int(attrs.getValue("v"))
                    except ValueError:
                        print "invalid number of lanes:", attrs.getValue("v")
                        self.WayList[self.CurrentidWay].Lanes = 1
                elif k =="length":
                    try:
                        self.WayList[self.CurrentidWay].WayLength = float(attrs.getValue("v")) 
                    except ValueError:
                        print "invalid WayLength:", attrs.getValue("v")
                        self.WayList[self.CurrentidWay].WayLength = 0
                        
    def endElement(self, name):
        if name == "way":    
            Delete = False            
            if self.Settings.has_key('AllowedWays'):
                if self.WayList[self.CurrentidWay].HighWayType in self.Settings['AllowedWays']:
                    pass
                else:
                    Delete = True
                 
            if self.WayList[self.CurrentidWay].NumberOfNodes() == 1:
                Delete = True
                
            if Delete:
                del  self.WayList[self.CurrentidWay]
            
            
            self.CurrentidWay= None
            
            
            
            
            
            
            
            
            
            
            
            
            
            
            
            
            