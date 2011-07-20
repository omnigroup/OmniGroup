// Copyright 2011 The Omni Group. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#include <tgmath.h>
#import <OmniQuartz/OQDrawing.h>
#import <OmniBase/OmniBase.h>

RCS_ID("$Id$")

/* Computes the Bezier curve which approximates a unit-circular arc, given that arc's chord (as dx,dy), the distance from the chord to the circle's center (h), and the chord's length (d). */
static void bezierForChord(CGFloat dx, CGFloat dy,
                           CGFloat h, CGFloat d,
                           CGFloat startx, CGFloat starty,
                           CGPoint *into)
{
    /* Circular arc approximation. Our two control points give us four degrees of freedom. Constraining the tangents to be perpendicular to the radii removes two degrees. Symmetry removes another. For the last degree of freedom, we choose a curve whose midpoint is at the correct distance from the center of the cirle: 1 unit from the center, or (1-h) from the midpoint of the chord. */
    /* TODO: Verify that that choice actually minimizes the error */
#define F ( (CGFloat)4 / (CGFloat)3 )
    CGFloat FHd = F * (1 - h) / d;
    CGFloat rise_x = - FHd * dy;
    CGFloat rise_y =   FHd * dx;
    // tangent constraint: rise/run = h / (d/2)   -->   Dcd = FHd * 2 * h / d = F * 2 * ( h - h*h ) / ( d*d )
    CGFloat Dcd = 2 * F * (h - h*h) / ( d*d );
    
    into[0].x = startx + rise_x + dx * Dcd;
    into[0].y = starty + rise_y + dy * Dcd;
    into[1].x = startx + rise_x + dx * (1 - Dcd);
    into[1].y = starty + rise_y + dy * (1 - Dcd);
#undef F
}

/* Computes the two Bezier curves which approximate a unit-circular arc, given that arc's chord (as dx,dy), the distance from the chord to the circle's center (h), and the chord's length (d).
 We subdivide the chord and call bezierForChord() for each half. */
static void doubleBezierForChord(CGFloat dx, CGFloat dy,
                                 CGFloat h, CGFloat d,
                                 CGFloat startx, CGFloat starty,
                                 CGPoint *into)
{
    /* join is the point on the perimeter at which we're splitting the curve */
    CGFloat joinX, joinY;
    
    /* s is the length of the new shorter chord
     sh, sH, etc are the corresponding other distances
     shs = sh / s; sHs = sH/s */
    CGFloat sh, s;
    
    if (d >= 1.999) {
        /* the input chord is a diameter of the circle; Hd = 1/2 */
        joinX = (dx - dy)/2;
        joinY = (dy + dx)/2;
        
        /* s = sqrt(1/2) * d, but if d>2 we want to scale everything up as if d=2. So s=sqrt(1/2)*2 = sqrt(2). */
        s = (CGFloat)M_SQRT2;
        sh = s / 2;
    } else {
        CGFloat Hd = (1 - h)/d;
        joinX = dx/2 - Hd * dy;
        joinY = dy/2 + Hd * dx;
        
        CGFloat sSquared = joinX*joinX + joinY*joinY;
        CGFloat shSquared = 1 - ( sSquared / 4 );
        sh = sqrt(shSquared);
        s = sqrt(sSquared);
    }
    
    bezierForChord(joinX, joinY, sh, s, startx, starty, into);
    into[2].x = startx + joinX;
    into[2].y = starty + joinY;
    bezierForChord(dx - joinX, dy - joinY, sh, s, startx + joinX, starty + joinY, into+3);
}

/*
 Computes the parameters of an elliptical arc as given by the SVG-style arc operator.
 delta is the vector from the start to the end of the arc.
 rMaj and rMin are the major and minor radii of the ellipse.
 theta is the angle of the major radius (0 -> towards positive X, pi/4 -> towards +X,+Y).
 largeSweep and posAngle disambiguate between the four possible fits to the above parameters.
 */
void OQComputeEllipseParameters(CGFloat deltaX, CGFloat deltaY,
                                CGFloat rMaj, CGFloat rMin, CGFloat theta,
                                BOOL largeSweep, BOOL posAngle,
                                struct OQEllipseParameters *result)
{
    CGFloat rSquared = fabs(rMaj*rMin);

    /* Transform the chord to unit circle. */
    /* The scaling isn't as important here as removing the elliptical shape, but making r=1 means one less thing to carry through the later math, so we go ahead and do that as well. */
    CGFloat uDeltaX, uDeltaY;
    
    /* 2x2 linear transform matrix to convert to unit circle */
    CGFloat m11, m22, mcross; /* m21 == m12, so we just use one variable for it */
    if (((rMaj-rMin)*(rMaj-rMin)) <= 0.001*rSquared) {
        CGFloat r = sqrt(rSquared);
        
        m11 = m22 = 1 / r;
        mcross = 0;

        uDeltaX = deltaX * m11;
        uDeltaY = deltaY * m22;
        
        /* Set up the transformation matrix for the inverse transform */
        m11 = m22 = r;
    } else {
        CGFloat cosTheta, sinTheta;
        
        cosTheta = cos(theta);
        sinTheta = sin(theta);
        
        m11 = ( cosTheta * cosTheta / rMaj + sinTheta * sinTheta / rMin );
        m22 = ( cosTheta * cosTheta / rMin + sinTheta * sinTheta / rMaj );
        mcross = cosTheta * sinTheta * ( 1/rMaj - 1/rMin );
        
        uDeltaX = deltaX * m11 + deltaY * mcross;
        uDeltaY = deltaY * m22 + deltaX * mcross;

        /* Set up the transformation matrix for the inverse transform */
        m11 = ( cosTheta * cosTheta * rMaj + sinTheta * sinTheta * rMin );
        m22 = ( cosTheta * cosTheta * rMin + sinTheta * sinTheta * rMaj );
        mcross = cosTheta * sinTheta * ( rMaj - rMin ); 
    }
    
    /* If we wanted to we could further rotate the matrix so that uDeltaY == 0.
     This would simplify some math, below (at the trivial cost of maintaining m21 & m12 instead of just mcross).
     Unfortunately we still need to have the complex implementations available for various cases, so there isn't much benefit.
     */    
    
    /* Initially we compute the result in transformed coordinates */
    int numSegments;
    CGPoint points[ 3 * 4 ];
    CGFloat centerX, centerY;
    
    /* Variable names:
     
     d   is the length of the chord (after we've rescaled to unit-circle coordinates)
     h   is the altitude from the midpoint of the chord to the center of the circle
     H   is the altitude from the midpoint of the chord to the circumference (h+H = 1)
     Hc  is the height of the control points above the chord
     
     */
    
    CGFloat dSquared = uDeltaX*uDeltaX + uDeltaY*uDeltaY;
    CGFloat hSquared = 1 - ( dSquared / 4 );                             /*  h^2 + (d/2)^2 = radius = 1 */
    CGFloat h;
    CGFloat d = sqrt(dSquared);
    
    /* Compute the center of the circle */
    centerX = uDeltaX / 2;
    centerY = uDeltaY / 2;
    if (hSquared <= 0) {
        // nothing?
        h = 0;
    } else {
        h = sqrt(hSquared);
        CGFloat hd = h / d;
        if (largeSweep)
            hd = -hd;
        centerY -= hd * uDeltaX;
        centerX += hd * uDeltaY;
    }
    
    if (dSquared <= 2.001) {
        if (!largeSweep) {
            /* The arc is less than 90 degrees (chord length <= sqrt(2)) and we want the small sweep. The result can be represented as a single cubic Bezier curve. */
            
            bezierForChord(uDeltaX, uDeltaY, h, d, 0, 0, &(points[0]));
            points[2].x = uDeltaX;
            points[2].y = uDeltaY;
            
            numSegments = 1;
        } else {
            /* The arc is 270 degrees or more. Split it into quarters. */
            CGFloat farpointX = centerX - uDeltaY / d;
            CGFloat farpointY = centerY + uDeltaX / d;
            CGFloat farpointDSquared = (farpointX*farpointX + farpointY*farpointY);
            CGFloat farpointHSquared = 1 - ( farpointDSquared / 4 );
            CGFloat farpointD = sqrt(farpointDSquared);
            CGFloat farpointH = sqrt(farpointHSquared);
            doubleBezierForChord(farpointX, farpointY, farpointH, farpointD, 0, 0, &(points[0]));
            points[5].x = farpointX;
            points[5].y = farpointY;
            doubleBezierForChord(uDeltaX - farpointX, uDeltaY - farpointY, farpointH, farpointD, farpointX, farpointY, &(points[6]));
            points[11].x = uDeltaX;
            points[11].y = uDeltaY;
            
            numSegments = 4;
        }
    } else if (!largeSweep || dSquared >= 3.999) {
        /* largeSweep=NO: The chord is larger than 90 degrees, but less than 180. Split it in half, and use a single Bezier for each half. */
        /* dSquared >= 4: The chord is the diameter of the ellipse, or very close, or impossibly large. Both sweeps are the same size, so the result just depends on posAngle. */
        
        doubleBezierForChord(uDeltaX, uDeltaY, h, d, 0, 0, &(points[0]));
        points[5].x = uDeltaX;
        points[5].y = uDeltaY;
        
        numSegments = 2;
    } else /* largeSweep */ {
        /* The chord is between 180 and 270 degrees. Split it into thirds. */
        CGFloat halfAlpha = (CGFloat)(M_PI / 3) - asin(d / 2) / 3;
        CGFloat t_h = cos(halfAlpha);
        CGFloat t_d = 2 * sin(halfAlpha);
        CGFloat far_midX = centerX - uDeltaY * (t_h / d);
        CGFloat far_midY = centerY + uDeltaX * (t_h / d);
        CGFloat far_offsX = uDeltaX * (t_d / d);
        CGFloat far_offsY = uDeltaY * (t_d / d);
        
        CGFloat x1 = far_midX - far_offsX/2;
        CGFloat y1 = far_midY - far_offsY/2;
        bezierForChord(x1, y1, t_h, t_d, 0, 0, &(points[0]));
        points[2].x = x1;
        points[2].y = y1;
        
        CGFloat x2 = far_midX + far_offsX/2;
        CGFloat y2 = far_midY + far_offsY/2;
        bezierForChord(far_offsX, far_offsY, t_h, t_d, x1, y1, &(points[3]));
        points[5].x = x2;
        points[5].y = y2;
        
        bezierForChord(uDeltaX - x2, uDeltaY - y2, t_h, t_d, x2, y2, &(points[6]));
        points[8].x = uDeltaX;
        points[8].y = uDeltaY;
        numSegments = 3;
    }
    
    result->numSegments = numSegments;
    /* Transform all points back to non-unit-circle coordinates and copy them to the output buffer */
    for(int pt = 0; pt < (3 * numSegments); pt++) {
        CGFloat px = points[pt].x;
        CGFloat py = points[pt].y;
        
        if (posAngle) {
            /* Reflect each point across the original chord vector, for the positive-sweep result */
            CGFloat baCosTheta = ( px * uDeltaX + py * uDeltaY ) / dSquared;
            px = 2 * uDeltaX * baCosTheta - px;
            py = 2 * uDeltaY * baCosTheta - py;
        }
        
        /* Apply the inverse transform we computed at the beginning */
        result->points[pt].x = px * m11 + py * mcross;
        result->points[pt].y = py * m22 + px * mcross;
    }
    result->center.x = centerX * m11 + centerY * mcross;
    result->center.y = centerY * m22 + centerX * mcross;
}

