# Create your views here.
# coding: utf-8
# !/opt/.venvs/wuwien/bin python

import json

import requests
from django.shortcuts import render
from geojson import Feature
from rest_framework.decorators import api_view
from rest_framework.response import Response

from django.conf import settings

from poi_manager.models import Poi, PoiCategory
from django.contrib.gis.db.models.functions import Centroid, AsGeoJSON

from django.http import  HttpResponse
from homepage import search_wu
from pprint import pprint
import logging

logr = logging.getLogger(__name__)


def get_client_ip(request):
    x_forwarded_for = request.META.get('HTTP_X_FORWARDED_FOR')
    if x_forwarded_for:
        ip = x_forwarded_for.split(',')[-1].strip()
    else:
        ip = request.META.get('REMOTE_ADDR')
    return ip


# takes a dict with searchcriteria, and returns the POI list.
# param: searchcriteria, containing data for searching. "type" attribute is mandatory!
# returns: a list with all pois (poi is represented as dict with lat, lon, layer,...)
# returns the entrance which is nearest to this room+

def create_terminal_start_json(query_result):
    '''

    :param query_result: psycopg2 response tuple or None
    :return: JSON of entrance for terminal start location
    '''
    returnList = []
    entranceCoords = json.loads(query_result[0])
    coords = entranceCoords['coordinates']
    entranceLayer = query_result[3]
    entranceEntry = {"lat": coords[1], "lon": coords[0], "layer": entranceLayer,
                     "routeNodeAttributes": {"name_de": query_result[2], "name_en": query_result[2],
                                             "layer": entranceLayer}, "terminalIp": query_result[4], }
    returnList.append(entranceEntry)
    terminal_start_json = json.dumps(returnList[0])
    return terminal_start_json


@api_view(['GET', ])
def get_terminal(request, format=None):
    """
    find IP of terminal and return start location
    """
    ipTerminal = get_client_ip(request)
    if ipTerminal == "127.0.0.1":
        # ipTerminal = "143.205.84.105"
        ipTerminal = "137.208.92.84"


    poi_qs = Poi.objects.filter(description=ipTerminal)

    if poi_qs:
        att = poi_qs.values()[0]

        if att['geom']:
            att['geom'] = None

        centroid_res = Poi.objects.annotate(json=AsGeoJSON(Centroid('geom'))).get(
            description=ipTerminal).json

        res = Feature(geometry=json.loads(centroid_res), properties=att)

        return Response(res)


@api_view(['GET', ])
def route_from_terminal(request, destination_location, format=None):
    if destination_location is None:
        return json.dumps({'myerror': 'destination_location param is None !  why we dont know not good'})
    else:

        terminal_data = get_terminal(request)

        start_d = terminal_data.data
        start_floor = str(start_d['properties']['floor_num'])
        start_coord_x = str(start_d['geometry']['coordinates'][0])
        start_coord_y = str(start_d['geometry']['coordinates'][1])

        startin = start_coord_x + "," + start_coord_y + "," + start_floor

        destination = search_wu.search_any(request, destination_location)

        dest_d = destination.data
        print(dest_d)


        dest_floor = str(dest_d['features'][0]['properties']['floor_num'])
        dest_coord_x = str(dest_d['features'][0]['properties']['centerGeometry']['coordinates'][0])
        dest_coord_y = str(dest_d['features'][0]['properties']['centerGeometry']['coordinates'][1])

        destin = dest_coord_x + "," + dest_coord_y + "," + dest_floor

        print(destin)

        final_q = destin + "&" + startin
        print(final_q)

        # print('/api/v1/directions/'+ fix_start_location + dest_coord + "," + dest_floor + "&0" )
        url = 'http://localhost:8000/indrz/api/v1/directions/' + final_q + '&0'
        route_to_book = requests.get(url)

        return Response(route_to_book.json())


@api_view(['GET'])
def route_from_kiosk(request, rvk_id, format=None):
    """
    Create a route directly to a book based on RVK key
    :param request:
    :param rvk_id: rvk_id
    :return: GeoJson linestring route from building entrance to book
    """

    fix_start_location = "1826545.2173675,6142423.4241214,0&"

    book_location_resp = rvk_call(request, rvk_id)

    resp = json.loads(str(book_location_resp.data))

    if resp['features'][1]['geometry']['type'] == 'Point':
        dest_floor = resp['features'][1]['properties']['floor']
        dest_coord_x = resp['features'][1]['geometry']['coordinates'][0]
        dest_coord_y = resp['features'][1]['geometry']['coordinates'][1]

        dest_coords = str(dest_coord_x) + "," + str(dest_coord_y)

        # print('/api/v1/directions/'+ fix_start_location + dest_coord + "," + dest_floor + "&0" )
        url = 'http://localhost:8000/api/v1/directions/' + fix_start_location + dest_coords + ',' + dest_floor + '&0'
        route_to_book = requests.get(url)

        return Response(route_to_book.json())


def homepage_kiosk(request, *args, **kwargs):
    context = {}
    if request.method == 'GET':

        poi_list = (
        "Study Area", "Surfstation", "Computer Rooms", "Scanner", "Search Terminal", "Self-Checkout", "Study Area",
        "Computer Desks", "Locker")

        poi_ids = ("43", "32", "33", "42", "62", "40", "41", "35", "44" )

        poi_cats_list = []

        for poi in poi_ids:
            poi_qs = PoiCategory.objects.get(pk=poi)

            poi_cats_list.append(poi_qs)


        map_name = kwargs.pop('map_name', None)
        building_id, = request.GET.get('buildingid', 1),
        campus_id = request.GET.get('campus', 1),
        space_id, = request.GET.get('spaceid', 0),
        zoom_level, = request.GET.get('zlevel', 17),
        route_from, = request.GET.get('startstr', ''),
        route_to, = request.GET.get('endstr', ''),
        centerx, = request.GET.get('centerx', 0),
        centery, = request.GET.get('centery', 0),
        floor_num, = request.GET.get('floor', 0),
        poi_name, = request.GET.get('poi-name', ''),

        floor_num = int(floor_num)

        if floor_num == 0:
            floor_num = floor_num + 1
        else:
            floor_num = floor_num + 1

        if isinstance(centerx, str):
            if ',' in centerx:
                centerx = float(centerx.replace(',', '.'))
                centery = float(centery.replace(',', '.'))

        context.update({
            'map_name': map_name,
            'building_id': building_id,
            'campus_id': campus_id,
            'space_id': int(space_id),
            'zoom_level': zoom_level,
            'route_from': route_from,
            'route_to': route_to,
            'centerx': centerx,
            'centery': centery,
            'floor_num': int(floor_num),
            'poi_name' : poi_name,
            'nodes': PoiCategory.objects.all(),
            'poi_cats': poi_cats_list,
        })

    return render(request, context=context, template_name='kiosk2.html')